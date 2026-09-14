import { describe, expect, test } from "bun:test";
import { EMPTY_CONTEXT, extraAddresses, parseAddress, pickCandidate, postalArea, type Candidate, type DossierContext } from "./address-resolve.ts";

const c = (id: string, city: string, postalCode: string, buildingId = `pand-${id}`): Candidate => ({ id, city, postalCode, buildingId });

describe("parseAddress", () => {
  test("street, number, suffix", () => {
    expect(parseAddress("Adamshofstraat 93A")).toEqual({ street: "Adamshofstraat", number: "93", suffix: "A" });
    expect(parseAddress("  Molenwal 15 te Oudewater")).toEqual({ street: "Molenwal", number: "15", suffix: "" });
    expect(parseAddress("1e Pijnackerstraat 12b")).toEqual({ street: "1e Pijnackerstraat", number: "12", suffix: "B" });
  });
  test("no number is no address", () => {
    expect(parseAddress("de fundering")).toBeNull();
    expect(parseAddress("Molenwal")).toBeNull();
  });
});

describe("postalArea", () => {
  test("four digits, tolerant of spacing and case", () => {
    expect(postalArea("3421 CK")).toBe("3421");
    expect(postalArea("3421ck")).toBe("3421");
    expect(postalArea(null)).toBeNull();
    expect(postalArea("CK 3421")).toBeNull();
  });
});

describe("pickCandidate", () => {
  const kerkstraat = [c("k-ams", "Amsterdam", "1012 AB"), c("k-rdam", "Rotterdam", "3011 AB"), c("k-rdam2", "Rotterdam", "3081 CD")];

  test("one candidate is taken, whatever the context", () => {
    expect(pickCandidate([kerkstraat[0]!], EMPTY_CONTEXT)).toBe("k-ams");
  });
  test("none is none", () => {
    expect(pickCandidate([], EMPTY_CONTEXT)).toBeNull();
  });
  test("ambiguous without context stays unresolved", () => {
    expect(pickCandidate(kerkstraat, EMPTY_CONTEXT)).toBeNull();
  });

  test("point 12: an address the nalezing's rapportage already links wins the tie", () => {
    const ctx: DossierContext = { ...EMPTY_CONTEXT, knownAddressIds: new Set(["k-rdam2"]) };
    expect(pickCandidate(kerkstraat, ctx)).toBe("k-rdam2");
  });
  test("two known candidates is still a tie", () => {
    const ctx: DossierContext = { ...EMPTY_CONTEXT, knownAddressIds: new Set(["k-rdam", "k-rdam2"]) };
    expect(pickCandidate(kerkstraat, ctx)).toBeNull();
  });

  test("point 13: the dossier's own pand wins", () => {
    const ctx: DossierContext = { ...EMPTY_CONTEXT, buildingId: "pand-k-rdam" };
    expect(pickCandidate(kerkstraat, ctx)).toBe("k-rdam");
  });
  test("point 13: one candidate in the dossier's city", () => {
    const ctx: DossierContext = { ...EMPTY_CONTEXT, city: "amsterdam" };
    expect(pickCandidate(kerkstraat, ctx)).toBe("k-ams");
  });
  test("point 13: two in the city, the postcode area decides", () => {
    const ctx: DossierContext = { ...EMPTY_CONTEXT, city: "Rotterdam", postalCode: "3081 ZZ" };
    expect(pickCandidate(kerkstraat, ctx)).toBe("k-rdam2");
  });
  test("two in the city, nothing to separate them: unresolved", () => {
    const ctx: DossierContext = { ...EMPTY_CONTEXT, city: "Rotterdam", postalCode: "3000 AA" };
    expect(pickCandidate(kerkstraat, ctx)).toBeNull();
    expect(pickCandidate(kerkstraat, { ...EMPTY_CONTEXT, city: "Rotterdam" })).toBeNull();
  });
});

describe("extraAddresses", () => {
  const byId = new Map<string, Candidate>([
    ["a15", c("a15", "Oudewater", "3421 CK", "pand-1")],
    ["a17", c("a17", "Oudewater", "3421 CK", "pand-2")],
    ["a19", c("a19", "Oudewater", "3421 CK", "pand-3")],
  ]);
  test("addresses off the dossier's pand, once each, first spelling kept", () => {
    const resolved = new Map<string, string | null>([
      ["Molenwal 15", "a15"],
      ["Molenwal 17", "a17"],
      ["Molenwal 17 te Oudewater", "a17"],
      ["Molenwal 19", "a19"],
      ["Molenwal 21", null],
    ]);
    expect(extraAddresses(resolved, byId, { ...EMPTY_CONTEXT, buildingId: "pand-1" })).toEqual([
      { addressId: "a17", addressText: "Molenwal 17" },
      { addressId: "a19", addressText: "Molenwal 19" },
    ]);
  });
  test("no pand on the dossier: every resolved address is extra", () => {
    const resolved = new Map<string, string | null>([["Molenwal 15", "a15"]]);
    expect(extraAddresses(resolved, byId, EMPTY_CONTEXT)).toEqual([{ addressId: "a15", addressText: "Molenwal 15" }]);
  });
});
