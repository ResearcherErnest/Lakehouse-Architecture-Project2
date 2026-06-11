# Athena Queries

All queries below are pre-saved as named queries in the Athena console (provisioned by the `athena` Terraform module).

Use the **primary workgroup** for analyst queries against the Gold layer, and the **engineering workgroup** for cross-layer queries including Silver.

---

## Daily Revenue by Department

Returns gross revenue, order count, and unique customers per department for the last 30 days.

```sql
SELECT
    order_date,
    department,
    order_count,
    unique_customers,
    gross_revenue,
    avg_order_value
FROM "ecom-lakehouse_gold"."daily_revenue"
WHERE order_date >= CURRENT_DATE - INTERVAL '30' DAY
ORDER BY order_date DESC, gross_revenue DESC;
```

---

## Top Products by Department (Current Month)

Returns the top 10 products per department ranked by units sold for the current calendar month.

```sql
SELECT
    department,
    product_name,
    units_sold,
    order_count,
    dept_revenue_rank,
    reorder_rate
FROM "ecom-lakehouse_gold"."product_performance"
WHERE order_year  = YEAR(CURRENT_DATE)
  AND order_month = MONTH(CURRENT_DATE)
  AND dept_revenue_rank <= 10
ORDER BY department, dept_revenue_rank;
```

---

## Customer Lifetime Value Distribution

Returns the top 100 customers by total spend for the current monthly snapshot.

```sql
SELECT
    user_id,
    total_orders,
    total_spend,
    avg_order_value,
    avg_days_between_orders,
    first_order_date,
    last_order_date
FROM "ecom-lakehouse_gold"."customer_orders"
WHERE snapshot_year  = YEAR(CURRENT_DATE)
  AND snapshot_month = MONTH(CURRENT_DATE)
ORDER BY total_spend DESC
LIMIT 100;
```

---

## Silver Data Quality Check

Validates Silver orders for null primary keys, invalid amounts, and missing timestamps. Run via the engineering workgroup.

```sql
SELECT
    COUNT(*)                                              AS total_rows,
    COUNT(CASE WHEN order_id IS NULL THEN 1 END)          AS null_order_ids,
    COUNT(CASE WHEN total_amount <= 0 THEN 1 END)         AS invalid_amounts,
    COUNT(CASE WHEN order_timestamp IS NULL THEN 1 END)   AS null_timestamps,
    COUNT(CASE WHEN user_id IS NULL THEN 1 END)           AS null_user_ids
FROM "ecom-lakehouse_silver"."orders";
```

---

## Time-Travel Query (Delta Lake)

Query a Silver table as it existed at a specific point in time (useful for debugging or auditing).

```sql
-- Athena does not natively support Delta time-travel syntax.
-- Use the Glue job or a Spark notebook with:
--   spark.read.format("delta").option("timestampAsOf", "2025-04-01").load("s3://lakehouse/silver/orders/")
-- or:
--   spark.read.format("delta").option("versionAsOf", 3).load("s3://lakehouse/silver/orders/")
```
