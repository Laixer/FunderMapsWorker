import { describe, expect, test } from "bun:test";
import { compare, currentValueText, normaliseName } from "./audit-compare.ts";

describe("audit compare", () => {
  test("missing when the database has nothing", () => {
    expect(compare("foundation_type", ["wood"], null)).toBe("missing");
    expect(compare("built_year", ["1913"], "")).toBe("missing");
  });
  test("enum equality", () => {
    expect(compare("foundation_type", ["wood_rotterdam"], "wood_rotterdam")).toBe("agrees");
    expect(compare("foundation_type", ["wood_rotterdam"], "concrete")).toBe("differs");
    expect(compare("foundation_quality", ["Tolerable"], "tolerable")).toBe("agrees");
  });
  test("built year compares the year, whatever the date format", () => {
    expect(compare("built_year", ["1913"], new Date("1913-01-01T00:00:00Z"))).toBe("agrees");
    expect(compare("built_year", ["1913"], "1913-01-01")).toBe("agrees");
    expect(compare("built_year", ["1912"], "1913-01-01")).toBe("differs");
  });
  test("levels within 5 mm agree, diameters within half a millimetre", () => {
    expect(compare("wood_level", ["-2.47"], "-2.472")).toBe("agrees");
    expect(compare("wood_level", ["-2.47"], "-2.41")).toBe("differs");
    expect(compare("pile_diameter_top", ["180"], "180.4")).toBe("agrees");
    expect(compare("pile_diameter_top", ["180"], "200")).toBe("differs");
  });
  test("candidate lists agree when any candidate matches", () => {
    expect(compare("damage_cause", ["drystand", "fungus_infection"], "fungus_infection")).toBe("agrees");
    expect(compare("damage_cause", ["drystand", "fungus_infection"], "subsidence")).toBe("differs");
  });
  test("'false' and 'none' against an empty cell is agreement, not a gap", () => {
    expect(compare("recovery_advised", ["false"], null)).toBe("agrees");
    expect(compare("crack_indoor_type", ["none"], null)).toBe("agrees");
    expect(compare("recovery_advised", ["true"], null)).toBe("missing");
    expect(compare("wood_level", ["0"], null)).toBe("missing");
  });
  test("booleans", () => {
    expect(compare("recovery_advised", ["true"], true)).toBe("agrees");
    expect(compare("recovery_advised", ["false"], "t")).toBe("differs");
  });
  test("contractor by normalised name and prefix", () => {
    expect(compare("contractor", ["Fugro GeoServices B.V."], "Fugro")).toBe("agrees");
    expect(compare("contractor", ["Wareco"], "Wareco Ingenieurs")).toBe("agrees");
    expect(compare("contractor", ["Duyts bouwconstructies"], "FunderMaps B.V.")).toBe("differs");
  });
  test("document date", () => {
    expect(compare("document_date", ["2014-11-03"], new Date("2014-11-03T00:00:00Z"))).toBe("agrees");
    expect(compare("document_date", ["2014-11-03"], "2026-09-01")).toBe("differs");
  });
  test("current value text", () => {
    expect(currentValueText("built_year", "1913-01-01")).toBe("1913");
    expect(currentValueText("wood_level", -2.47)).toBe("-2.47");
    expect(currentValueText("foundation_type", null)).toBeNull();
    expect(normaliseName("Techniek & Methode B.V.")).toBe("techniek en methode");
  });
});
