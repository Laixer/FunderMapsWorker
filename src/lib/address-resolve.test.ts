import { describe, expect, test } from "bun:test";
import { EMPTY_CONTEXT, extraAddresses, inSpans, parseAddress, parseAddressList, pickCandidate, postalArea, selectListedAddresses, type Candidate, type DossierContext, type ListedAddress } from "./address-resolve.ts";

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

describe("parseAddressList (#186)", () => {
  const spans = (t: string) => parseAddressList(t)?.spans ?? null;

  test("dash range, same parity, steps by two", () => {
    expect(parseAddressList("Olympiaweg 20-92")).toEqual({ street: "Olympiaweg", spans: [{ from: 20, fromSuffix: "", to: 92, toSuffix: "", step: 2 }] });
    expect(spans("Uiterwaardenstraat 85-87")).toEqual([{ from: 85, fromSuffix: "", to: 87, toSuffix: "", step: 2 }]);
  });
  test("t/m in its spellings; mixed parity takes every number", () => {
    expect(spans("Driedijk 32 t/m 38")).toEqual([{ from: 32, fromSuffix: "", to: 38, toSuffix: "", step: 2 }]);
    expect(spans("Driedijk 35 t/m 38")).toEqual([{ from: 35, fromSuffix: "", to: 38, toSuffix: "", step: 1 }]);
    expect(spans("Driedijk 32 tot en met 38")?.[0]?.to).toBe(38);
    expect(spans("Driedijk 32 t / m 38")?.[0]?.to).toBe(38);
  });
  test("Don's 157730: range with a lettered end plus explicit extras", () => {
    expect(parseAddressList("Harddraverstraat 46 t/m 52A, 52C en 54C")).toEqual({
      street: "Harddraverstraat",
      spans: [
        { from: 46, fromSuffix: "", to: 52, toSuffix: "A", step: 2 },
        { from: 52, fromSuffix: "C", to: 52, toSuffix: "C", step: 1 },
        { from: 54, fromSuffix: "C", to: 54, toSuffix: "C", step: 1 },
      ],
    });
  });
  test("a plain list is a list", () => {
    expect(spans("Newtonstraat 64 en 66")?.length).toBe(2);
    expect(spans("Newtonstraat 64, 66 & 68")?.length).toBe(3);
  });
  test("not a list: one address, a toevoeging, a postcode, nonsense spans", () => {
    expect(parseAddressList("Adamshofstraat 93A")).toBeNull();
    expect(parseAddressList("Molenwal 15 te Oudewater")).toBeNull();
    expect(parseAddressList("Bankastraat 25-1")).toBeNull();
    expect(parseAddressList("Jacob Obrechtstraat 37-2")).toBeNull();
    expect(parseAddressList("Kerkstraat 2-4")).toBeNull();
    expect(parseAddressList("Kerkstraat 2-3")).toBeNull();
    expect(parseAddressList("Kerkstraat 12, 1234 AB Amsterdam")).toBeNull();
    expect(parseAddressList("Dorpsstraat 1-999")).toBeNull();
    expect(parseAddressList("de fundering")).toBeNull();
  });
});

describe("inSpans / selectListedAddresses (#186)", () => {
  const row = (n: string, city = "Amsterdam", b = `pand-${n.replace(/\D/g, "")}`): ListedAddress =>
    ({ id: `a-${n}-${city}`, buildingNumber: n, street: "X", buildingId: b, city, postalCode: "1000 AA" });

  test("parity: 85-87 never takes 86", () => {
    const l = parseAddressList("X 85-87")!;
    expect(["85", "86", "87", "87A", "89"].filter((n) => inSpans(n, l.spans))).toEqual(["85", "87", "87A"]);
  });
  test("a bare number takes every unit (Olympiaweg's H units)", () => {
    const l = parseAddressList("Olympiaweg 20-92")!;
    expect(["22H", "24H", "92H", "23H", "94H"].filter((n) => inSpans(n, l.spans))).toEqual(["22H", "24H", "92H"]);
  });
  test("157730 lands on exactly the eleven addresses the BAG has", () => {
    const l = parseAddressList("Harddraverstraat 46 t/m 52A, 52C en 54C")!;
    const bag = ["46A", "46B", "46C", "48B", "48C", "50A", "50B", "50C", "52A", "52B", "52C", "54A", "54B", "54C", "47", "56"];
    expect(bag.filter((n) => inSpans(n, l.spans))).toEqual(["46A", "46B", "46C", "48B", "48C", "50A", "50B", "50C", "52A", "52C", "54C"]);
  });
  test("a lettered start bounds its own number", () => {
    const l = parseAddressList("X 46B t/m 50")!;
    expect(["46", "46A", "46B", "46C", "48", "50C"].filter((n) => inSpans(n, l.spans))).toEqual(["46B", "46C", "48", "50C"]);
  });
  test("units written with a toevoeging belong to their number (Stadionweg 259-H, 261-2)", () => {
    const l = parseAddressList("Stadionweg 259-261")!;
    expect(["259-H", "259-1", "260-1", "261-2", "261-4", "263-1"].filter((n) => inSpans(n, l.spans))).toEqual(["259-H", "259-1", "261-2", "261-4"]);
  });
  test("a lettered single stays exact, toevoeging or not", () => {
    const l = parseAddressList("X 46 en 52C")!;
    expect(["52", "52C", "52C-1", "52B", "46-H"].filter((n) => inSpans(n, l.spans))).toEqual(["52C", "52C-1", "46-H"]);
  });

  const l = parseAddressList("Kerkstraat 10-12")!;
  const rows = [row("10"), row("12"), row("10", "Haarlem"), row("12", "Haarlem")];
  test("the dossier's city picks the street", () => {
    expect(selectListedAddresses(l, rows, { ...EMPTY_CONTEXT, city: "haarlem" }).map((r) => r.city)).toEqual(["Haarlem", "Haarlem"]);
  });
  test("two cities and no context: no expansion, not a guess", () => {
    expect(selectListedAddresses(l, rows, EMPTY_CONTEXT)).toEqual([]);
  });
  test("one city: taken", () => {
    expect(selectListedAddresses(l, rows.slice(0, 2), EMPTY_CONTEXT).length).toBe(2);
  });
});
