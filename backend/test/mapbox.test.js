import assert from "node:assert/strict";
import test from "node:test";

import {
  createMapboxProvider,
  mapMapboxManeuver,
  mapMapboxTrafficStatus,
} from "../src/mapbox-provider.js";
import { createMapboxPlacesProvider } from "../src/mapbox-places.js";

const bogotaRouteRequest = {
  origin: {
    coordinate_system: "WGS84",
    longitude_deg: -74.072092,
    latitude_deg: 4.710989,
  },
  destination: {
    coordinate_system: "WGS84",
    longitude_deg: -74.053889,
    latitude_deg: 4.675833,
  },
};

test("maneuver and traffic mappings translate Mapbox responses accurately", () => {
  assert.equal(mapMapboxManeuver({ maneuver: { type: "depart", modifier: "" } }), "continue");
  assert.equal(mapMapboxManeuver({ maneuver: { type: "turn", modifier: "right" } }), "right");
  assert.equal(mapMapboxManeuver({ maneuver: { type: "turn", modifier: "left" } }), "left");
  assert.equal(mapMapboxManeuver({ maneuver: { type: "roundabout", modifier: "" } }), "roundabout");
  assert.equal(mapMapboxManeuver({ maneuver: { type: "arrive", modifier: "" } }), "arrive");

  assert.equal(mapMapboxTrafficStatus("low"), "free_flow");
  assert.equal(mapMapboxTrafficStatus("moderate"), "slow");
  assert.equal(mapMapboxTrafficStatus("heavy"), "congested");
  assert.equal(mapMapboxTrafficStatus("severe"), "severe");
});

test("refuses to create Mapbox provider without token", () => {
  assert.throws(() => createMapboxProvider({ key: "" }), /Mapbox access token is required/);
  assert.throws(() => createMapboxPlacesProvider({ key: "" }), /Mapbox access token is required/);
});

test("transforms Mapbox route response into Protocol v1 RouteBundle", async () => {
  const fakeMapboxResponse = {
    code: "Ok",
    routes: [
      {
        duration: 1200,
        distance: 8500,
        geometry: {
          type: "LineString",
          coordinates: [
            [-74.072092, 4.710989],
            [-74.06, 4.69],
            [-74.053889, 4.675833],
          ],
        },
        legs: [
          {
            summary: "Carrera 7",
            steps: [
              {
                maneuver: {
                  type: "depart",
                  instruction: "Dirígete al norte por Carrera 7",
                  location: [-74.072092, 4.710989],
                },
                distance: 500,
                duration: 60,
                name: "Carrera 7",
              },
              {
                maneuver: {
                  type: "turn",
                  modifier: "right",
                  instruction: "Gira a la derecha en Calle 100",
                  location: [-74.06, 4.69],
                },
                distance: 8000,
                duration: 1140,
                name: "Calle 100",
              },
            ],
            annotation: {
              congestion: ["low", "moderate"],
            },
          },
        ],
      },
    ],
  };

  const fetchImpl = async () => new Response(JSON.stringify(fakeMapboxResponse), { status: 200 });
  const provider = createMapboxProvider({ key: "pk.test_token", fetchImpl });
  const route = await provider.planRoute(bogotaRouteRequest);

  assert.equal(route.total_duration_s, 1200);
  assert.equal(route.total_distance_m, 8500);
  assert.equal(route.maneuvers.length, 2);
  assert.equal(route.maneuvers[0].instruction, "Dirígete al norte por Carrera 7");
  assert.equal(route.maneuvers[1].type, "right");
  assert.equal(route.polyline.length, 3);
});

test("transforms Mapbox geocoding features into POI search response", async () => {
  const fakeGeocodingResponse = {
    type: "FeatureCollection",
    features: [
      {
        id: "poi.123",
        text: "Parque de la 93",
        place_name: "Parque de la 93, Bogotá, Colombia",
        center: [-74.053, 4.676],
        context: [
          { id: "place.456", text: "Bogotá" },
          { id: "neighborhood.789", text: "Chicó" },
        ],
      },
    ],
  };

  const fetchImpl = async () => new Response(JSON.stringify(fakeGeocodingResponse), { status: 200 });
  const placesProvider = createMapboxPlacesProvider({ key: "pk.test_token", fetchImpl });
  const result = await placesProvider.searchPlaces({
    keywords: "Parque de la 93",
    origin: { longitude_deg: -74.072, latitude_deg: 4.71 },
  });

  assert.equal(result.places.length, 1);
  const p = result.places[0];
  assert.equal(p.name, "Parque de la 93");
  assert.equal(p.city, "Bogotá");
  assert.equal(p.district, "Chicó");
  assert.ok(p.distance_m > 0);
});
