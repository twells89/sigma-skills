-- Burst recipients for the store operating report: one row per store.
-- The store manager receives the report; stores without a matching manager fall
-- back to the store inbox. EMPLOYEE_ID is not unique in EMPLOYEES, so the join
-- also requires ROLE = 'manager' and the same STORE_ID.
-- Export the result as recipients.csv for draft-burst-schedules.rb.
WITH mgr AS (
  SELECT STORE_ID, EMPLOYEE_ID, EMAIL
  FROM EXAMPLES.COLD_PROVISIONS.EMPLOYEES
  WHERE ROLE = 'manager'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY STORE_ID, EMPLOYEE_ID ORDER BY HIRE_DATE DESC) = 1
)
SELECT
  s.STORE_ID AS store_id,
  s.STORE_NAME AS store_name,
  COALESCE(e.EMAIL, s.STORE_EMAIL) AS recipient_email,
  IFF(e.EMAIL IS NULL, 'store inbox', 'store manager') AS recipient_type
FROM EXAMPLES.COLD_PROVISIONS.STORES s
LEFT JOIN mgr e
  ON e.EMPLOYEE_ID = s.STORE_MANAGER_ID
 AND e.STORE_ID = s.STORE_ID
ORDER BY s.STORE_ID;
