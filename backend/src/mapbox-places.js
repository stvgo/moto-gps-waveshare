import { fetchGetWithTransientRetry } from "./upstream-retry.js";

const DEFAULT_GEOCODING_ENDPOINT = "https://api.mapbox.com/geocoding/v5/mapbox.places";
const PHOTON_ENDPOINT = "https://photon.komoot.io/api/";
const MAX_RESULTS = 12;

export class MapboxPlacesError extends Error {
  constructor(code, message, { retryable = true } = {}) {
    super(message);
    this.name = "MapboxPlacesError";
    this.code = code;
    this.retryable = retryable;
  }
}

function compactText(value, maximumLength) {
  if (Array.isArray(value)) value = value.join(" / ");
  return String(value ?? "").trim().slice(0, maximumLength);
}

function distanceMetres(left, right) {
  const toRadians = (degrees) => (degrees * Math.PI) / 180;
  const latitude1 = toRadians(left.latitude_deg);
  const latitude2 = toRadians(right.latitude_deg);
  const latitudeDelta = latitude2 - latitude1;
  const longitudeDelta = toRadians(right.longitude_deg - left.longitude_deg);
  const halfLatitude = Math.sin(latitudeDelta / 2);
  const halfLongitude = Math.sin(longitudeDelta / 2);
  const haversine =
    halfLatitude * halfLatitude +
    Math.cos(latitude1) * Math.cos(latitude2) * halfLongitude * halfLongitude;
  return Math.round(6_371_000 * 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine)));
}

async function searchPhotonPlaces(keywords, origin, fetchImpl, signal) {
  try {
    const url = new URL(PHOTON_ENDPOINT);
    url.searchParams.set("q", keywords);
    url.searchParams.set("limit", String(MAX_RESULTS));
    if (origin && Number.isFinite(origin.longitude_deg) && Number.isFinite(origin.latitude_deg)) {
      url.searchParams.set("lat", String(origin.latitude_deg));
      url.searchParams.set("lon", String(origin.longitude_deg));
    } else {
      // Default Colombia center
      url.searchParams.set("lat", "4.711");
      url.searchParams.set("lon", "-74.072");
    }

    const response = await fetchImpl(url, {
      headers: { Accept: "application/json", "User-Agent": "MOTO-GPS/1.0" },
      signal,
    });
    if (!response.ok) return [];

    const data = await response.json();
    const features = Array.isArray(data?.features) ? data.features : [];
    const results = [];

    for (const f of features) {
      const p = f.properties ?? {};
      const isColombia = p.countrycode === "CO" || p.country === "Colombia" || !p.country;
      if (!isColombia) continue;
      if (!Array.isArray(f.geometry?.coordinates) || f.geometry.coordinates.length < 2) continue;

      const [lon, lat] = f.geometry.coordinates;
      const point = { longitude_deg: lon, latitude_deg: lat };
      const name = compactText(p.name || p.street || keywords, 96);
      const city = compactText(p.city || p.district || p.state || "Colombia", 32);
      const district = compactText(p.district || p.locality || "", 32);
      const addressParts = [p.street, p.housenumber, city, p.state].filter(Boolean);
      const address = compactText(addressParts.join(", ") || name, 160);

      const place = {
        id: compactText(String(p.osm_id || Math.random()), 64),
        name,
        address,
        city,
        district,
        display_area: [city, district].filter(Boolean).join(" · ") || city,
        location: point,
      };

      if (origin) {
        place.distance_m = distanceMetres(origin, point);
      }
      results.push(place);
    }
    return results;
  } catch {
    return [];
  }
}

export function createMapboxPlacesProvider({
  key,
  endpoint = DEFAULT_GEOCODING_ENDPOINT,
  fetchImpl = globalThis.fetch,
  timeoutMs = 6000,
} = {}) {
  if (typeof key !== "string" || key.trim() === "") {
    throw new MapboxPlacesError("SERVER_MISCONFIGURED", "Mapbox access token is required", {
      retryable: false,
    });
  }

  return {
    async searchPlaces(query, { signal } = {}) {
      const keywords = compactText(query?.keywords, 120);
      if (!keywords) {
        return { protocol_version: 1, query: "", places: [] };
      }

      const deadlineSignal = AbortSignal.timeout(timeoutMs);
      const requestSignal = signal ? AbortSignal.any([signal, deadlineSignal]) : deadlineSignal;
      const origin = query?.origin;

      // 1. Try smart POI search (finds malls, parks, commercial points across Colombia)
      const photonResults = await searchPhotonPlaces(keywords, origin, fetchImpl, requestSignal);
      if (photonResults.length > 0) {
        return {
          protocol_version: 1,
          query: keywords,
          places: photonResults.slice(0, MAX_RESULTS),
        };
      }

      // 2. Fallback to Mapbox Geocoding (exact street addresses, numbers)
      const encodedQuery = encodeURIComponent(keywords);
      const url = new URL(`${endpoint}/${encodedQuery}.json`);
      url.searchParams.set("access_token", key);
      url.searchParams.set("limit", String(MAX_RESULTS));
      url.searchParams.set("types", "poi,address,neighborhood,locality,place");
      url.searchParams.set("country", "co");

      if (origin && Number.isFinite(origin.longitude_deg) && Number.isFinite(origin.latitude_deg)) {
        url.searchParams.set("proximity", `${origin.longitude_deg},${origin.latitude_deg}`);
      }

      let response;
      try {
        response = await fetchGetWithTransientRetry(fetchImpl, url, {
          headers: { Accept: "application/json" },
          signal: requestSignal,
        });
      } catch (error) {
        throw new MapboxPlacesError("PROVIDER_UNAVAILABLE", `Mapbox search error: ${error.message}`);
      }

      if (!response.ok) {
        throw new MapboxPlacesError("PROVIDER_HTTP_ERROR", `Mapbox geocoding returned ${response.status}`);
      }

      const payload = await response.json();
      const features = Array.isArray(payload.features) ? payload.features : [];
      const places = [];

      for (const f of features) {
        if (!f || !Array.isArray(f.center) || f.center.length < 2) continue;
        const [lon, lat] = f.center;
        const point = { longitude_deg: lon, latitude_deg: lat };

        let city = "";
        let district = "";
        if (Array.isArray(f.context)) {
          for (const c of f.context) {
            if (c.id?.startsWith("place.")) city = c.text;
            if (c.id?.startsWith("locality.") || c.id?.startsWith("neighborhood.")) district = c.text;
          }
        }

        const place = {
          id: compactText(f.id, 64),
          name: compactText(f.text || f.place_name, 96),
          address: compactText(f.place_name, 160),
          city: compactText(city, 32),
          district: compactText(district, 32),
          display_area: [city, district].filter(Boolean).join(" · ") || compactText(f.place_name, 64),
          location: point,
        };

        if (origin) {
          place.distance_m = distanceMetres(origin, point);
        }

        places.push(place);
      }

      return {
        protocol_version: 1,
        query: keywords,
        places,
      };
    },

    async searchCities({ keywords }) {
      return {
        protocol_version: 1,
        keywords,
        cities: [],
      };
    },
  };
}
