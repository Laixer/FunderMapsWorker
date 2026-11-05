-- Studio #32: everyone staff today gets the role, so who may use the Studio doesn't change when the API moves to it.
--
-- True on prod 2026-11-04: FunderMaps B.V. (d8c19418-c832-4c91-8993-84b8ed641448, the API's PLATFORM_ORGANIZATION_ID) has 11
-- members: 2 administrators, who stay administrator and count as staff, and 9 users, who become staff here. Those 9 include the
-- service accounts, which have the same access today (a role of their own can come when something needs the difference).
-- Membership stays as it is: it still decides data scope and billing.
UPDATE application."user" u
   SET role = 'staff', updated_at = now()
 WHERE u.role = 'user'
   AND EXISTS (
     SELECT 1 FROM application.organization_user ou
      WHERE ou.user_id = u.id AND ou.organization_id = 'd8c19418-c832-4c91-8993-84b8ed641448');

-- The two sets must be the same, or the deploy after this locks someone out or lets someone in.
DO $$
DECLARE
  missing integer;
  extra integer;
BEGIN
  SELECT count(*) INTO missing FROM application."user" u
   WHERE u.role = 'user' AND EXISTS (
     SELECT 1 FROM application.organization_user ou
      WHERE ou.user_id = u.id AND ou.organization_id = 'd8c19418-c832-4c91-8993-84b8ed641448');
  SELECT count(*) INTO extra FROM application."user" u
   WHERE u.role <> 'user' AND NOT EXISTS (
     SELECT 1 FROM application.organization_user ou
      WHERE ou.user_id = u.id AND ou.organization_id = 'd8c19418-c832-4c91-8993-84b8ed641448');
  IF missing > 0 OR extra > 0 THEN
    RAISE EXCEPTION 'staff and platform members differ: % members without the role, % with it outside the org', missing, extra;
  END IF;
END $$;
