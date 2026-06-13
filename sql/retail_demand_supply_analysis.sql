SELECT * FROM module3.sqlsync;

ALTER TABLE sqlsync
RENAME COLUMN ï»¿week_start_date TO week_start_date;

ALTER TABLE sqlsync
RENAME TO trend_week_facts;

SELECT trend_key, COUNT(*) AS total_weeks
FROM trend_week_facts
GROUP BY trend_key;

CREATE VIEW trend_gap_layer AS
SELECT
    week_start_date,
    trend_key,
    demand_index,
    units_sold,
    units_sold - demand_index AS gap_units,
    CASE
        WHEN units_sold - demand_index > 0 THEN 1
        WHEN units_sold - demand_index < 0 THEN -1
        ELSE 0
    END AS gap_sign
FROM trend_week_facts;

SELECT *
FROM trend_gap_layer
ORDER BY trend_key, week_start_date
LIMIT 20;

CREATE VIEW trend_persistence_layer AS
SELECT
    *,
    CASE
        WHEN gap_sign = LAG(gap_sign)
             OVER (PARTITION BY trend_key ORDER BY week_start_date)
        THEN 1
        ELSE 0
    END AS persistence_flag
FROM trend_gap_layer;

SELECT trend_key, week_start_date, gap_sign, persistence_flag
FROM trend_persistence_layer
ORDER BY trend_key, week_start_date;

CREATE VIEW trend_run_break_layer AS
SELECT
    *,
    CASE
        WHEN gap_sign != LAG(gap_sign)
             OVER (PARTITION BY trend_key ORDER BY week_start_date)
        THEN 1
        ELSE 0
    END AS run_break
FROM trend_gap_layer;

SELECT trend_key, week_start_date, gap_sign, run_break
FROM trend_run_break_layer
ORDER BY trend_key, week_start_date;

CREATE VIEW trend_run_layer AS
SELECT
    *,
    SUM(COALESCE(run_break,0))
        OVER (PARTITION BY trend_key ORDER BY week_start_date) AS run_id
FROM trend_run_break_layer;

SELECT trend_key, week_start_date, gap_sign, run_id
FROM trend_run_layer
ORDER BY trend_key, week_start_date;

CREATE VIEW trend_run_length_layer AS
SELECT
    *,
    COUNT(*) OVER (PARTITION BY trend_key, run_id) AS run_length
FROM trend_run_layer;

SELECT trend_key,
       MIN(run_id),
       MAX(run_id),
       MAX(run_length)
FROM trend_run_length_layer
GROUP BY trend_key;

CREATE VIEW trend_financial_layer AS
SELECT
    *,
    CASE
        WHEN trend_key = 'sportswear' THEN 1500
        WHEN trend_key = 'cargo_pants' THEN 2000
    END AS asp,
    CASE
        WHEN gap_sign = -1 THEN ABS(gap_units) *
            CASE
                WHEN trend_key = 'sportswear' THEN 1500
                WHEN trend_key = 'cargo_pants' THEN 2000
            END
        ELSE 0
    END AS lost_revenue,
    CASE
        WHEN gap_sign = 1 THEN gap_units *
            CASE
                WHEN trend_key = 'sportswear' THEN 1500
                WHEN trend_key = 'cargo_pants' THEN 2000
            END * 0.30
        ELSE 0
    END AS markdown_loss
FROM trend_run_length_layer;

SELECT * 
FROM trend_financial_layer;

CREATE VIEW trend_summary AS
SELECT
    trend_key,
    SUM(lost_revenue) AS total_lost_revenue,
    SUM(markdown_loss) AS total_markdown_loss,
    SUM(lost_revenue + markdown_loss) AS total_financial_impact,
    MAX(run_length) AS max_run_length,
    AVG(persistence_flag) AS persistence_rate
FROM trend_persistence_layer
JOIN trend_financial_layer
USING (week_start_date, trend_key)
GROUP BY trend_key;

SELECT *
FROM trend_summary;

CREATE OR REPLACE VIEW trend_week_facts_final AS
SELECT
    week_start_date,
    trend_key,
    demand_index,
    units_sold,
    gap_units,
    gap_sign,

    -- persistence flag (same as run_break inverted logic)
    CASE 
        WHEN run_break = 0 AND run_id IS NOT NULL THEN 1
        ELSE 0
    END AS persistence_flag,

    run_id,
    run_length,
    asp,
    lost_revenue,
    markdown_loss,

    (lost_revenue + markdown_loss) AS total_weekly_impact

FROM trend_financial_layer;

CREATE TABLE trend_week_facts_final_table AS
SELECT * FROM trend_week_facts_final;

SELECT COUNT(*) FROM trend_week_facts_final_table;

CREATE TABLE trend_summary_snapshot AS
SELECT * FROM trend_summary;

SELECT *
FROM trend_week_facts_final_table;

SELECT *
FROM trend_summary_snapshot;