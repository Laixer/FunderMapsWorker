UPDATE public.pand SET identificatie = concat('NL.IMBAG.PAND.', identificatie);
CREATE INDEX pand_identificatie_idx ON public.pand USING btree (identificatie);

UPDATE public.ligplaats SET identificatie = concat('NL.IMBAG.LIGPLAATS.', identificatie);
CREATE INDEX ligplaats_identificatie_idx ON public.ligplaats USING btree (identificatie);

UPDATE public.standplaats SET identificatie = concat('NL.IMBAG.STANDPLAATS.', identificatie);
CREATE INDEX standplaats_identificatie_idx ON public.standplaats USING btree (identificatie);

--

UPDATE public.verblijfsobject SET nummeraanduiding_hoofdadres_identificatie = concat('NL.IMBAG.NUMMERAANDUIDING.', nummeraanduiding_hoofdadres_identificatie);
CREATE INDEX verblijfsobject_nummeraanduiding_hoofdadres_identificatie_idx ON public.verblijfsobject USING btree (nummeraanduiding_hoofdadres_identificatie);

UPDATE public.verblijfsobject SET pand_identificatie = concat('NL.IMBAG.PAND.', pand_identificatie);
CREATE INDEX verblijfsobject_pand_identificatie_idx ON public.verblijfsobject USING btree (pand_identificatie);

UPDATE public.verblijfsobject SET identificatie = concat('NL.IMBAG.VERBLIJFSOBJECT.', identificatie);
CREATE INDEX verblijfsobject_identificatie_idx ON public.verblijfsobject USING btree (identificatie);
