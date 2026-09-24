import { describe, expect, test } from "bun:test";
import { duplicateNote, inquiryRegistrations, readRegistrations, sharedRegistration } from "./qs-registration.ts";

// Layout text as pdftotext -layout prints a Funderingsattest (FM2026-000323).
const ATTEST = `
Adres                          Pand Identificatienummer        Uitvoerder                     NAFO-ID
Zoutmansweg 100                0595100000003963                A. Inspecteur                  466353453-25-016
                                                               Datum opname                   Onderzoeksmethode
Wijze van vaststelling         Woningtype                      23 september 2026              Fase 0 Funderingsrisico
 Registratienummer              Datum registratie
 105901                         23 september 2026
`;

describe("readRegistrations", () => {
  test("the attest's registration number, never the inspector's NAFO-ID", () => {
    const r = readRegistrations(ATTEST, "Funderingsattest_en_toelichting.pdf");
    expect(r.map((x) => `${x.system}:${x.number}`)).toEqual(["nafo:105901"]);
  });

  test("an attest's file name carries the registration number", () => {
    const r = readRegistrations("", "105895-Funderingsattest_en_toelichting.pdf");
    expect(r.map((x) => `${x.system}:${x.number}`)).toEqual(["nafo:105895"]);
  });

  test("a number at the start of any other file name is not a registration", () => {
    expect(readRegistrations("", "1943_NL-RtSA_396-03_P56-43-1943_T001.jpg")).toEqual([]);
    expect(readRegistrations("", "507793-offerte.pdf")).toEqual([]);
  });

  test("a FunderConsult REG number, with or without the dash", () => {
    const r = readRegistrations("Certificaat QuickScan REG-0002392\nkenmerk REG 0002110", null);
    expect(r.map((x) => `${x.system}:${x.number}`)).toEqual(["funderconsult:0002392", "funderconsult:0002110"]);
  });

  test("a report from another bureau has no registration", () => {
    const fugro = "QuickScan Funderingsonderzoek | Rotterdam\n507793 - S1028763 | 4 september 2026\nFugro-projectnr. 507793 - S1028763";
    expect(readRegistrations(fugro, "Bijlage_-_Quickscan_Fundering (1).pdf")).toEqual([]);
  });

  test("text and file name naming the same number count once", () => {
    const r = readRegistrations(ATTEST.replace("105901", "105895"), "105895-Funderingsattest.pdf");
    expect(r).toHaveLength(1);
  });
});

describe("inquiryRegistrations", () => {
  test("NAFO from a fundonservice note", () => {
    const r = inquiryRegistrations("QS-FOS-577796", "FRO-quickscan 6787 — NAFO 105901 — doorlevering vanuit FunderConsult (bron: fundonservice).");
    expect(r.map((x) => `${x.system}:${x.number}`)).toEqual(["nafo:105901"]);
  });

  test("REG from a FunderScan inquiry, counted once", () => {
    const r = inquiryRegistrations("QS-FS-REG-0002392", "FunderScan REG-0002392 — doorlevering vanuit FunderConsult.");
    expect(r.map((x) => `${x.system}:${x.number}`)).toEqual(["funderconsult:0002392"]);
  });

  test("the FOS id in the document name is not the NAFO registration", () => {
    expect(inquiryRegistrations("QS-FOS-560855", null)).toEqual([]);
  });
});

describe("sharedRegistration", () => {
  test("same system and number is a match, leading zeros ignored", () => {
    const hit = sharedRegistration(
      [{ system: "funderconsult", number: "2392", evidence: "" }],
      [{ system: "funderconsult", number: "0002392", evidence: "" }],
    );
    expect(hit?.number).toBe("2392");
  });

  test("the same digits in another system are not a match", () => {
    expect(sharedRegistration(
      [{ system: "nafo", number: "105901", evidence: "" }],
      [{ system: "funderconsult", number: "105901", evidence: "" }],
    )).toBeNull();
  });
});

describe("duplicateNote", () => {
  test("names the registration and the date of the QuickScan we already have", () => {
    const note = duplicateNote({ system: "nafo", number: "105895", evidence: "" }, "2026-09-23");
    expect(note).toBe("Deze QuickScan (registratienummer 105895) stond al in FunderMaps, van 23-09-2026. Er is niets veranderd; het risico houdt er al rekening mee.");
  });
});
