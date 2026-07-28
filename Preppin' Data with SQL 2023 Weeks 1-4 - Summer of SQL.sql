
// 2023 - week 01 - 3 outputs 
// Output 1
select split_part(transaction_code, '-', 1) as bank
, sum(value) as Value
from pd2023_wk01
group by bank;

// Output 2
select split_part(transaction_code, '-', 1) as bank
, iff(online_or_in_person = 1, 'Online', 'In-Person') as online_or_in_person
, dayname(to_date(transaction_date, 'DD/MM/YYYY HH24:MI:SS')) as transaction_date
, sum(value) as Value
from pd2023_wk01
group by 1,2,3;

// Output 3
select split_part(transaction_code, '-', 1) as bank
, customer_code
, Sum(value) as value
from pd2023_wk01
group by 1,2;

//------
// 2023 - week 02 - 1 output 
select transaction_id
, concat('GB', s.check_digits, s.swift_code, replace(t.sort_code, '-', ''), t.account_number)
from pd2023_wk02_transactions t
left join pd2023_wk02_swift_codes s
    on t.bank = s.bank;

//------
// 2023 - week 03 - 1 output 
with targets as (
select online_or_in_person
, replace(quarter, 'Q', '') as quarter
, quarterly_target
from pd2023_wk03_targets
unpivot(quarterly_target for quarter in (Q1, Q2, Q3, Q4))
), 

transact as (
select iff(online_or_in_person = 1, 'Online', 'In-Person') as online_or_in_person
, to_char(quarter(to_date(transaction_date, 'DD/MM/YYYY HH24:MI:SS'))) as quarter
, value
from pd2023_wk01 
)

select tr.online_or_in_person
, tr.quarter
, sum(tr.value) as value
, t.quarterly_target
from transact tr
inner join targets t
on t.online_or_in_person = tr.online_or_in_person
and t.quarter = tr.quarter
group by tr.online_or_in_person
, tr.quarter
, t.quarterly_target;


//------

