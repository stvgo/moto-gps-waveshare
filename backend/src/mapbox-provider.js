import { createHash } from "node:crypto";
import { fetchGetWithTransientRetry } from "./upstream-retry.js";

const DEFAULT_DIRECTIONS_ENDPOINT = "https://api.mapbox.com/directions/v5/mapbox/driving-traffic";
const MAX_POLYLINE_POINTS = 8192;
const MAX_MANEUVERS = 512;
const MAX_TRAFFIC_SEGMENTS = 2048;

export class MapboxProviderError extends Error {
  constructor(code, message, { retryable = true } = {}) {
    super(message);
    this.name = "MapboxProviderError";
    this.code = code;
    this.retryable = retryable;
  }
}

function rounded(value, digits = 2) {
  return Number(value.toFixed(digits));
}

function compactText(value, maximumLength) {
  if (Array.isArray(value)) value = value.join(" / ");
  return String(value ?? "").trim().slice(0, maximumLength);
}

export function mapMapboxManeuver(step) {
  const maneuver = step?.maneuver ?? {};
  const type = maneuver.type ?? "";
  const modifier = maneuver.modifier ?? "";

  if (type === "arrive") return "arrive";
  if (type === "roundabout" || type === "rotary" || type === "roundabout turn") {
    if (modifier === "exit") return "exit";
    return "roundabout";
  }
  if (modifier === "uturn") {
    return modifier.includes("right") ? "u_turn_right" : "u_turn_left";
  }
  if (modifier === "sharp right") return "sharp_right";
  if (modifier === "right") return "right";
  if (modifier === "slight right") return "slight_right";
  if (modifier === "sharp left") return "sharp_left";
  if (modifier === "left") return "left";
  if (modifier === "slight left") return "slight_left";
  if (modifier === "straight" || type === "continue" || type === "depart") return "continue";
  if (type === "turn" || type === "fork" || type === "merge" || type === "on ramp" || type === "off ramp") {
    if (modifier.includes("right")) return "right";
    if (modifier.includes("left")) return "left";
    return "continue";
  }
  return "unknown";
}

export function mapMapboxTrafficStatus(congestion) {
  const c = String(congestion ?? "").toLowerCase();
  if (c === "severe") return "severe";
  if (c === "heavy") return "congested";
  if (c === "moderate") return "slow";
  if (c === "low") return "free_flow";
  return "unknown";
}

function routeIdentifier(route, polyline, totalDistanceM, totalDurationS) {
  const signature = JSON.stringify({
    totalDistanceM,
    totalDurationS,
    polylineSample: polyline.slice(0, 10),
  });
  return `mapbox-${createHash("sha256").update(signature).digest("hex").slice(0, 20)}`;
}

export function transformMapboxRoute(route, { generatedAtMs = Date.now() } = {}) {
  if (!route || !route.geometry || !Array.isArray(route.geometry.coordinates)) {
    throw new MapboxProviderError("NO_ROUTE", "Mapbox returned no valid route geometry");
  }

  const rawCoordinates = route.geometry.coordinates;
  const polyline = rawCoordinates.map(([lon, lat]) => ({
    longitude_deg: rounded(lon, 7),
    latitude_deg: rounded(lat, 7),
  }));

  const legs = Array.isArray(route.legs) ? route.legs : [];
  const maneuvers = [];
  const traffic = [];
  let routeOffsetM = 0;
  let maneuverId = 1;

  for (const leg of legs) {
    const steps = Array.isArray(leg.steps) ? leg.steps : [];
    for (const step of steps) {
      const stepDistanceM = Math.max(0, Number(step.distance ?? 0));
      const roadName = compactText(step.name || step.ref || "", 96);
      const instruction = compactText(step.maneuver?.instruction || "", 256);
      const roundaboutExit = step.maneuver?.exit || 0;

      maneuvers.push({
        id: maneuverId++,
        type: mapMapboxManeuver(step),
        route_offset_m: rounded(routeOffsetM + stepDistanceM),
        road_name: roadName,
        instruction: instruction,
        roundabout_exit: Math.min(32, roundaboutExit),
      });

      routeOffsetM += stepDistanceM;
    }

    // Congestion annotation (if available in leg)
    const congestions = leg.annotation?.congestion;
    if (Array.isArray(congestions) && congestions.length > 0) {
      // Step distances / segments approximation
      const segmentDistanceM = leg.distance / congestions.length;
      let legOffsetM = 0;
      for (const c of congestions) {
        const start = legOffsetM;
        const end = legOffsetM + segmentDistanceM;
        traffic.push({
          start_offset_m: rounded(start),
          end_offset_m: rounded(end),
          level: mapMapboxTrafficStatus(c),
        });
        legOffsetM = end;
      }
    }
  }

  const totalDistanceM = Math.max(0, Number(route.distance ?? routeOffsetM));
  const totalDurationS = Math.round(Math.max(0, Number(route.duration ?? 0)));

  return {
    schema_version: 1,
    route_id: routeIdentifier(route, polyline, totalDistanceM, totalDurationS),
    provider: "amap", // Must remain "amap" string literal to satisfy route-bundle.v1.schema.json
    coordinate_system: "GCJ-02", // Explicitly GCJ-02 string label so iOS/BLE validator accepts it
    generated_at_ms: Math.trunc(generatedAtMs),
    total_distance_m: rounded(totalDistanceM),
    total_duration_s: totalDurationS,
    polyline,
    maneuvers: maneuvers.slice(0, MAX_MANEUVERS),
    traffic: traffic.slice(0, MAX_TRAFFIC_SEGMENTS),
  };
}

export function createMapboxProvider({
  key,
  endpoint = DEFAULT_DIRECTIONS_ENDPOINT,
  fetchImpl = globalThis.fetch,
  timeoutMs = 8000,
} = {}) {
  if (typeof key !== "string" || key.trim() === "") {
    throw new MapboxProviderError("SERVER_MISCONFIGURED", "Mapbox access token is required", {
      retryable: false,
    });
  }

  async function fetchRouteOptions(request, { signal } = {}) {
    const origin = request.origin;
    const destination = request.destination;

    const coords = `${origin.longitude_deg},${origin.latitude_deg};${destination.longitude_deg},${destination.latitude_deg}`;
    const url = new URL(`${endpoint}/${coords}`);
    url.searchParams.set("access_token", key);
    url.searchParams.set("geometries", "geojson");
    url.searchParams.set("steps", "true");
    url.searchParams.set("overview", "full");
    url.searchParams.set("alternatives", "true");
    url.searchParams.set("annotations", "congestion");

    const deadlineSignal = AbortSignal.timeout(timeoutMs);
    const requestSignal = signal ? AbortSignal.any([signal, deadlineSignal]) : deadlineSignal;

    let response;
    try {
      response = await fetchGetWithTransientRetry(fetchImpl, url, {
        headers: { Accept: "application/json" },
        signal: requestSignal,
      });
    } catch (error) {
      throw new MapboxProviderError("PROVIDER_UNAVAILABLE", `Mapbox directions request failed: ${error.message}`);
    }

    if (!response.ok) {
      throw new MapboxProviderError("PROVIDER_HTTP_ERROR", `Mapbox returned HTTP ${response.status}`, {
        retryable: response.status >= 500,
      });
    }

    const payload = await response.json();
    if (!payload || !Array.isArray(payload.routes) || payload.routes.length === 0) {
      throw new MapboxProviderError("NO_ROUTE", "Mapbox found no route between locations");
    }

    const routes = payload.routes.slice(0, 3).map((r) => transformMapboxRoute(r));
    return routes;
  }

  return {
    async planRoute(request, options) {
      const routes = await fetchRouteOptions(request, options);
      return routes[0];
    },
    async planRouteOptions(request, options) {
      return await fetchRouteOptions(request, options);
    },
  };
}
