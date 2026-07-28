// Week 7: Preppin' Data with SQL 2023 Weeks 9-12

// 2023 - week 09 - 1 output
// Combine transactions data
with transactions as (select tp.transaction_id
, transaction_date
, value
, account_to
, account_from
from pd2023_wk07_transaction_detail td
left join pd2023_wk07_transaction_path tp
on tp.transaction_id = td.transaction_id
where cancelled_ <> 'Y'
), 

// Calculate values based on to and from assigning negatives for from. 
account_transactions as (select transaction_id 
, account_type
, account as account_id
, transaction_date as value_date
, case when
    account_type = 'ACCOUNT_TO' then value
    when account_type = 'ACCOUNT_FROM' then -value
    end as transaction_value
, null as balance
from transactions
unpivot(
    account for account_type in (account_to, account_from))
),

// Union the two datasets read for calculations (account info and the one created above)
merged as (select account_number as account_id
, balance_date as value_date
, null as transaction_value
, balance
from pd2023_wk07_account_information
UNION ALL
select account_id
, value_date
, transaction_value
, balance
from account_transactions
), // remove comma for wk9 output

// Created running calculation
wk09_output as (select account_id
, value_date
, transaction_value
, sum(coalesce(transaction_value, balance)) over (
    partition by account_id
    order by value_date asc
    rows between unbounded preceding and current row
) as balance
from merged
order by account_id, value_date asc
), 
//; to get Week 9 output include semicolon. Week 10 below follows on from Week 9

//-----

// 2023 - week 10 - 1 output

// First aggregate so 1 value per date
wk09_output_agg as (select account_id
, value_date
, sum(transaction_value) as transaction_value
, sum(balance) as balance
from wk09_output
group by account_id, value_date
), 

// Create data scaffold for the dates between 31st Jan and 14th Feb
date_scaffold as (select dateadd(day, seq4(), '2023-01-31'::date) as value_date
from table(generator(rowcount => 15)) // calculate how many days in between or use ROWCOUNT => DATEDIFF(day, '2023-01-31'::date, '2023-02-14'::date) + 1
),

/* Checking scaffold is correct
select *
from date_scaffold
order by value_date; 
*/

// Now add date scaffold to each account_id
join_scaffold as (select  m.account_id
, ds.value_date
from (select distinct account_id
        from merged) m
cross join date_scaffold ds
)

/* Checking scaffold is correct
select * 
from join_scaffold
*/

// Final output, left join scaffolded to aggregated values table, and update null values in balance
select js.account_id 
, js.value_date
, woa.transaction_value
, last_value(woa.balance) ignore nulls over (
        partition by js.account_id 
        order by js.value_date 
        rows between unbounded preceding and current row
    ) as balance
from join_scaffold js
left join wk09_output_agg woa
on js.account_id = woa.account_id 
and js.value_date = woa.value_date
order by js.account_id, js.value_date asc;

//-----

// 2023 - week 11 - 1 output

// Create radian lat and long for each table
with customer_loc as (select customer
, address_long / (180/pi()) as address_long_r
, address_lat / (180/pi()) as address_lat_r
from pd2023_wk11_dsb_customer_locations
),

branches as (select branch
, branch_long / (180/pi()) as branch_long_r
, branch_lat / (180/pi()) as branch_lat_r
from pd2023_wk11_dsb_branches
), 

// Calculate distance and cross join (to append)
distance as (select *
, 3963 * acos(
    sin(address_lat_r) * sin(branch_lat_r)
    + cos(address_lat_r) * cos(branch_lat_r) 
    * cos(branch_long_r - address_long_r)
    ) as distance_miles
from customer_loc 
cross join branches 
), 

// Find closest bank based on shortest distance
closest as (select *
from distance
qualify row_number() over (
    partition by customer
    order by distance_miles // default is asc - disclose if desc
) = 1
order by branch asc, distance_miles asc
)

// Find priority rank and rename headers
select branch
, branch_long_r as branch_long
, branch_lat_r as branch_lat
, distance_miles as distance
, row_number() over (
    partition by branch
    order by distance_miles
) as customer_priority
, customer
, address_long_r as address_long
, address_lat_r as address_lat
from closest;


//-----

// 2023 - week 12 - 1 output

// Fill year in bank holiday table
with year_filled as (select date
, last_value(nullif(year, '')) ignore nulls over(
    order by row_num
    rows between unbounded preceding and current row
) as year
, bank_holiday
from pd2023_wk12_uk_bank_holidays
), 

// Convert to date
date_bank_hols as (select to_date(date || '-' || year, 'DD-MON-YYYY') as bank_hol_date
, bank_holiday
from year_filled
where nullif(date, '') is not null
), 

// Join to customer dataset and create reporting day flag based on NOT bank holiday or a weekend
// Flag the end of the month (so new customers that date will be assigned to next day where not already not a reporting day)
joined_customers_hols as (select nc.new_customers as no_customers
, to_date(nc.date, 'DD/MM/YYYY') as date_joined
, bank_hol_date
, dayofweek(date_joined) as day_number
, case when bank_hol_date is not null or day_number in (5,6) then null
    else 'Y'
    end as flag
from date_bank_hols dbh
right join pd2023_wk12_new_customers nc
on to_date(nc.date, 'DD/MM/YYYY') = dbh.bank_hol_date
order by date_joined asc
), 


// if reporting is not that day assign customer to next reporting date (create a grouping field)
groups as (select no_customers
, date_joined
, day_number 
, flag
, case when date_joined = last_day(date_joined) 
    and (flag = 'Y') then 'Y'
    end as last_day_month
, count(case when flag= 'Y' then 1 end) over (
    order by date_joined asc
    rows between current row and unbounded following // look t current row and all after until Y found.
) as reporting_group
from joined_customers_hols 
order by date_joined asc
),

// Flip reporting day calc so where reporting_group is highest should be 1 (so reverse number)
// Calculate reporting day for each month - then group by reporting date
// Where date is last day of month, assign next month. 
reporting_day as (select reporting_group
, max(date_joined) as reporting_date
, to_char(case when 
    max(date_joined) = last_day(max(date_joined)) // Where latest date_joined in the current group = last day of that month
    then dateadd('month', 1, max(date_joined)) // Move to next month when last date
    else max(date_joined)
    end, 'YYYY-MM'
    ) as reporting_month
, sum(no_customers) as new_customers
from groups
group by reporting_group
order by reporting_date
),

// Assign reporting days resetting for each month
uk_customers as (select reporting_month
, row_number() over(
    partition by reporting_month
    order by reporting_date asc
    ) as reporting_day 
, reporting_date
, sum(new_customers) as new_customers
from reporting_day
group by reporting_date, reporting_month, reporting_date
order by reporting_date
),

// Check outcome of output
// select *
// from reporting_day_final 

// Convert ROi data 
ireland_customers as (select to_char(to_date(reporting_month, 'Mon-YY'), 'YYYY-MM') as reporting_month // Converted to later compare Uk and ROi dates
, new_customers as new_customers
, reporting_day
, to_date(reporting_date, 'DD/MM/YYYY') as reporting_date
from pd2023_wk12_roi_new_customers 
order by reporting_month, reporting_day
),

// Full join to retrieve combined output
// As dates new_customers joined may be different, use coalese to pick up missing values from either of the two datasets
full_join as (select coalesce(uc.reporting_month, ic.reporting_month) as reporting_month
, coalesce(uc.reporting_day, ic.reporting_day) as reporting_day
, coalesce(uc.reporting_date, ic.reporting_date) as reporting_date
// fill null customer counts with 0 for clean output
, coalesce(uc.new_customers, 0) as uk_new_customers
, coalesce(ic.new_customers, 0) as roi_new_customers
// Keep to see which dates don't align and values need to be assigned. 
, uc.reporting_date as uk_reporting_date
, ic.reporting_date as roi_reporting_date
// keep roi reporting month for misalignment flagging
, ic.reporting_month as roi_reporting_month,
from uk_customers uc
full outer join ireland_customers ic
    on uc.reporting_date = ic.reporting_date -- must have join condition
// exclude 2024 dates cleanly as specified
  where coalesce(uc.reporting_month, ic.reporting_month) != '2024-01'
),

// Check values
// select *
// from full_join

// Where not UK reporting day but ROi reporting day, assign new customers to next UK reporting day
// Reformat roi month 
assign_customers_to_uk as (select 
case when roi_reporting_month is null
    then 'Y'
    end as misalignment_flag
, reporting_month
, reporting_day
, reporting_date
, uk_new_customers // Add to uk value the below calculation
    + coalesce(
    lag(case when uk_new_customers = 0 and roi_new_customers <> 0 // Carry ROI new customers forward to the next reporting date when UK new customers are 0
    then roi_new_customers 
    end) over (
        order by reporting_date
        ),
        0 // Most rows don't have anything to carry forward, so LAG returns NULL - make 0
      ) as uk_new_customers
, roi_new_customers
, to_char(to_date(roi_reporting_month || '-01'), 'MON-YY') AS roi_reporting_month // Make date with -01 (for day), then convert to format wanted
from full_join
order by reporting_date
), 

// Filter out where uk customers are 0 as that is not a reporting day
final_output as (select * 
from assign_customers_to_uk
where uk_new_customers !=0
)

select *
from final_output
