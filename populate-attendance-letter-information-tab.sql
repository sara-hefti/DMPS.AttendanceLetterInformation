/*******************
DMPS
Populate Attendance Letter Information tab

source = [desmoinesia.infinitecampus.org,7772].dev2.dbo.ch_MargiAttendance_tbl
destination: Student Information > General > Attendance Letter Information

Multiple Steps:
1. Collect data from the Dev2 "Margi Attendance Table" into #all
2. For students with >1 record in the #all table, fix them based off of the following rules:
		- students with >1 primary school. Pick the record with the most recent NineDatePrimary date
		- students with 1 primary and >1 secondary; pull the secondary entry with lowest ABPercentSecond and set secondarySchool='Central'
		- students with no primary and >1 secondary; the secondary entry with the highest percentage goes to Primary section; lowest percentage stays in secondary section
3. For students who are missing attendance data for their Primary enrollment in Margi Table, calculate attendance data for primary enrollment using ch_mins table
4. For students who are missing attendance data for their Secondary enrollment in Margi Table, calculate attendance data for secondary enrollment using ch_mins table

select * from #odds order by studentNumber
select * from #students_secondary_calc
select * from #students_primary_calc

********************/

if Object_ID('tempdb..#odds') is not Null drop table #odds
if Object_ID('tempdb..#all') is not Null drop table #all

-- get data into full table
select studentNumber, lastname, firstname, school, primeschoolId, ninedateprimary, ABpercentprime, AbsentDaysPrime, scheduleDayPrime, 
	   secondaryschool, secondschoolid, nineDateSecondary, ABPercentsecond, AbsentDaysSecond, ScheduleDaysSecond
into #all
from [desmoinesia.infinitecampus.org,7772].dev2.dbo.ch_MargiAttendance_tbl
where (primeschoolId is not null or secondschoolId is not null)



-- collects the "odds" - these are students with >1 record in the table; there should only be one record per student
select studentNumber, lastname, firstname, school, primeschoolId, ninedateprimary, ABpercentprime, AbsentDaysPrime, scheduleDayPrime, 
	   secondaryschool, secondschoolid, nineDateSecondary, ABPercentsecond, AbsentDaysSecond, ScheduleDaysSecond
into #odds
from #all
where  studentNumber IN (select studentNumber
						from #all
						group by studentNumber
						having count(studentNumber) >1
						)
order by lastname, firstname

-- remove the odds from the all table; we'll add the correct records for the odds in next
delete from #all
where studentNumber in (select studentNumber from #odds)


insert into #all
select x.*
from (
			-- students with >1 primary school. Pick the record with the most recent NineDatePrimary date
			select a.*
			from #odds a
			inner join #odds b on b.studentNumber=a.studentNumber and b.school <> a.school and a.nineDatePrimary > b.nineDatePrimary
			--where school is not null


			union

			-- students with 1 primary and >1 secondary; pull the secondary entry with lowest ABPercentSecond and set secondarySchool='Central'
			select distinct a.studentNumber, a.lastname, a.firstname, a.school, a.primeschoolId, a.ninedateprimary, a.ABpercentprime, 
				   a.AbsentDaysPrime, a.scheduleDayPrime, 'Central', a.secondschoolid, a.nineDateSecondary, a.ABPercentsecond, a.AbsentDaysSecond, a.ScheduleDaysSecond
			-- select a.*
			from #odds a
			inner join #odds b on b.studentNumber=a.studentNumber and b.secondarySchool <> a.secondarySchool and a.ABPercentsecond < b.ABPercentsecond
			where a.secondarySchool IN ('Academy', 'Campus') and b.secondarySchool IN ('Academy', 'Campus') and a.school IS NOT NULL

			union

			-- students with no primary and >1 secondary; the secondary entry with the highest percentage goes to Primary section; lowest percentage stays in secondary section
			select distinct a.studentNumber, a.lastname, a.firstname, 'Central' school, a.secondschoolId primeschoolId, a.nineDateSecondary ninedateprimary, a.ABPercentsecond ABpercentprime, 
				   a.absentDaysSecond AbsentDaysPrime, a.scheduleDaysSecond scheduleDayPrime, 

				   'Central' secondaryschool, b.secondschoolid, b.nineDateSecondary, b.ABPercentsecond, b.AbsentDaysSecond, b.ScheduleDaysSecond
			-- select *
			from #odds a
			inner join #odds b on b.studentNumber=a.studentNumber and b.secondarySchool <> a.secondarySchool and a.ABPercentsecond > b.ABPercentsecond
			where a.secondarySchool IN ('Academy', 'Campus') and b.secondarySchool IN ('Academy', 'Campus') and a.school IS NULL
	) x


	
------------------------------------------------------------------------------------
-- if student already has the attribute but the value is different, update
------------------------------------------------------------------------------------
update cs
	set cs.value=x.value,
		cs.date= cast(getDate() as smalldatetime)
--select i.lastname, i.firstname, x.*, cs.*
from (
		select studentNumber, 4134 attributeId, school value, 'PrimarySchool' element
		from #all

		union

		select studentNumber, 4130 attributeId, cast(primeschoolId as varchar(3)), 'PrimeSchoolID'
		from #all

		union

		select studentNumber, 4125 attributeId, convert(varchar(10), NineDatePrimary, 101), 'NineDatePrimary'
		from #all

		union

		select studentNumber, 4122 attributeId, cast(cast(Abpercentprime * 100 as decimal(6,2)) as varchar(6)) + '%', 'ABpercentprime'
		from #all

		union

		select studentNumber, 4123 attributeId, cast(cast(AbsentDaysPrime as decimal(6,2)) as varchar(10)), 'AbsentDaysPrime'
		from #all

		union

		select studentNumber, 4124 attributeId, cast(ScheduleDayPrime as varchar(3)), 'ScheduleDayPrime'
		from #all

		union

		select studentNumber, 4539 attributeId, secondaryschool, 'SecondarySchool'
		from #all

		union

		select studentNumber, 4131 attributeId, cast(secondschoolId as varchar(3)), 'SecondSchoolID'
		from #all

		union

		select studentNumber, 4126 attributeId, convert(varchar(10), NineDateSecondary, 101), 'NineDateSecondary'
		from #all

		union

		select studentNumber, 4127 attributeId, cast(cast(ABPercentSecond * 100 as decimal(7,2)) as varchar(6)) + '%', 'ABPercentSecond'
		from #all

		union

		select studentNumber, 4128 attributeId, cast(cast(AbsentDaysSecond as decimal(6,2)) as varchar(10)), 'AbsentDaysSecond'  
		from #all

		union

		select studentNumber, 4129 attributeId, cast(ScheduleDaysSecond as varchar(20)), 'ScheduleDaySecond'
		from #all

	) x
inner join person p on p.studentNumber=x.studentNumber
inner join [identity] i on i.identityId=p.currentIdentityId
left join customStudent cs on cs.personId=p.personId and cs.attributeID=x.attributeId
where ISNULL(cs.value,'') <> x.value



------------------------------------------------------------------------------------
-- if student does not have the attribute, INSERT it.
------------------------------------------------------------------------------------
INSERT INTO customStudent (personId, attributeId, value, date, districtId)
select distinct i.personId, x.attributeId, x.value, cast(getDate() as smalldatetime), (select districtId from campusVersion)
--select i.lastname, i.firstname, x.*, cs.*
from (
		select studentNumber, 4134 attributeId, school value, 'PrimarySchool' element
		from #all

		union

		select studentNumber, 4130 attributeId, cast(primeschoolId as varchar(3)), 'PrimeSchoolID'
		from #all

		union

		select studentNumber, 4125 attributeId, convert(varchar(10), NineDatePrimary, 101), 'NineDatePrimary'
		from #all

		union

		select studentNumber, 4122 attributeId, cast(cast(Abpercentprime * 100 as decimal(6,2)) as varchar(6)) + '%', 'ABpercentprime'
		from #all

		union

		select studentNumber, 4123 attributeId, cast(cast(AbsentDaysPrime as decimal(6,2)) as varchar(10)), 'AbsentDaysPrime'
		from #all

		union

		select studentNumber, 4124 attributeId, cast(ScheduleDayPrime as varchar(3)), 'ScheduleDayPrime'
		from #all

		union

		select studentNumber, 4539 attributeId, secondaryschool, 'SecondarySchool'
		from #all

		union

		select studentNumber, 4131 attributeId, cast(secondschoolId as varchar(3)), 'SecondSchoolID'
		from #all

		union

		select studentNumber, 4126 attributeId, convert(varchar(10), NineDateSecondary, 101), 'NineDateSecondary'
		from #all

		union

		select studentNumber, 4127 attributeId, cast(cast(ABPercentSecond * 100 as decimal(7,2)) as varchar(6)) + '%', 'ABPercentSecond'
		from #all
		
		union

		select studentNumber, 4128 attributeId, cast(cast(AbsentDaysSecond as decimal(6,2)) as varchar(10)), 'AbsentDaysSecond'  
		from #all

		union

		select studentNumber, 4129 attributeId, cast(ScheduleDaysSecond as varchar(20)), 'ScheduleDaySecond'
		from #all

		union

		select studentNumber, 4132 attributeId, '1', 'CurrentTerm'
		from #all

	) x
inner join person p on p.studentNumber=x.studentNumber
inner join [identity] i on i.identityId=p.currentIdentityId
left join customStudent cs on cs.personId=p.personId and cs.attributeID=x.attributeId
where cs.attributeId is null and x.value is not null




/*****************************************************************************************
-- If student is missing attendance data for their Primary enrollment in Margi Table:

-- calculate attendance data for primary enrollment using ch_mins table
-- run update / insert statements to populate to Attendance Letter Info tab


*****************************************************************************************/

if Object_ID('tempdb..#students_primary_calc') is not Null drop table #students_primary_calc

			select  
				x.personId, 
				a.studentNumber,
				a.lastname, 
				a.firstname, 
				x.school,
				cast(cast(sum(totalschedule_byDay_absences) as decimal(6,2)) as varchar(10)) absent_days, 
				cast(max(dayno) as varchar(3)) days_scheduled, 
				cast(cast(100 - ((sum(totalschedule_byDay_absences) / max(dayno)) *100) as decimal(6,2)) as varchar(6)) + '%' att_rate
			into #students_primary_calc
			from [desmoinesia.infinitecampus.org,7772].dev2.dbo.Ch_mins_by_day_comp_20251 x
			inner join #all a on a.studentNumber = x.studentNumber
			inner join enrollment e on e.personId=x.personId and e.calendarId=x.calendarId 
			where e.serviceType='P'
			and e.startDate IN (select max(startDate) from enrollment where calendarId=e.calendarId and personId=e.personId and serviceType=e.serviceType)
			and e.endDate is null
			and a.studentNumber in (select studentNumber from #all where school is null)
			group by x.personId, a.studentNumber, a.lastname, a.firstname, x.school




update cs
	set cs.value=x.value,
		cs.date= cast(getDate() as smalldatetime)
--select i.lastname, i.firstname, x.*, cs.*
from (
		select studentNumber, 4134 attributeId, school value, 'PrimarySchool' element
		from #students_primary_calc

		union

		select studentNumber, 4122 attributeId, att_rate, 'ABpercentprime'
		from #students_primary_calc

		union

		select studentNumber, 4123 attributeId, absent_days, 'AbsentDaysPrime'
		from #students_primary_calc

		union

		select studentNumber, 4124 attributeId, days_scheduled, 'ScheduleDayPrime'
		from #students_primary_calc

	) x
inner join person p on p.studentNumber=x.studentNumber
inner join [identity] i on i.identityId=p.currentIdentityId
left join customStudent cs on cs.personId=p.personId and cs.attributeID=x.attributeId
where ISNULL(cs.value,'') <> x.value


------------------------------------------------------------------------------------
-- if student does not have the attribute, INSERT it.
------------------------------------------------------------------------------------
INSERT INTO customStudent (personId, attributeId, value, date, districtId)
select distinct i.personId, x.attributeId, x.value, cast(getDate() as smalldatetime), (select districtId from campusVersion)
-- select i.lastname, i.firstname, x.*, cs.*
from (
		select studentNumber, 4134 attributeId, school value, 'PrimarySchool' element
		from #students_primary_calc

		union

		select studentNumber, 4122 attributeId, att_rate, 'ABpercentprime'
		from #students_primary_calc

		union

		select studentNumber, 4123 attributeId, absent_days, 'AbsentDaysPrime'
		from #students_primary_calc

		union

		select studentNumber, 4124 attributeId, days_scheduled, 'ScheduleDayPrime'
		from #students_primary_calc

		union

		select studentNumber, 4132 attributeId, '1', 'CurrentTerm'
		from #students_primary_calc

	) x
inner join person p on p.studentNumber=x.studentNumber
inner join [identity] i on i.identityId=p.currentIdentityId
left join customStudent cs on cs.personId=p.personId and cs.attributeID=x.attributeId
where cs.attributeId is null and x.value is not null




/*****************************************************************************************
-- If student is missing attendance data for their Secondary enrollment in Margi Table:

-- calculate attendance data for Secondary enrollment using ch_mins table
-- run update / insert statements to populate to Attendance Letter Info tab


*****************************************************************************************/

if Object_ID('tempdb..#students_secondary_calc') is not Null drop table #students_secondary_calc


			select  
				x.personId, 
				a.studentNumber,
				a.lastname, 
				a.firstname, 
				x.school,
				cast(cast(sum(totalschedule_byDay_absences) as decimal(6,2)) as varchar(10)) absent_days, 
				cast(max(dayno) as varchar(3)) days_scheduled, 
				cast(cast(100 - ((sum(totalschedule_byDay_absences) / max(dayno)) *100) as decimal(6,2)) as varchar(6)) + '%' att_rate,
				cast(cast(sum(totalschedule_byDay_absences) / max(dayno) * 100 as decimal(6,2)) as varchar(6)) + '%' absent_pct
			into #students_secondary_calc
			from [desmoinesia.infinitecampus.org,7772].dev2.dbo.Ch_mins_by_day_comp_20251 x
			inner join #all a on a.studentNumber = x.studentNumber
			inner join enrollment e on e.personId=x.personId and e.calendarId=x.calendarId 
			where e.serviceType='S'
			and e.startDate IN (select max(startDate) from enrollment where calendarId=e.calendarId and personId=e.personId and serviceType=e.serviceType)
			and e.endDate is null
			and a.studentNumber in (select studentNumber from #all where secondschoolId is null)
			group by x.personId, a.studentNumber, a.lastname, a.firstname, x.school



update cs
	set cs.value=x.value,
		cs.date= cast(getDate() as smalldatetime)
-- select i.lastname, i.firstname, x.*, cs.*
from (
		select studentNumber, 4539 attributeId, school value, 'SecondarySchool' element
		from #students_secondary_calc

		union

		select studentNumber, 4127 attributeId, att_rate, 'ABPercentSecond'
		from #students_secondary_calc

		union

		select studentNumber, 4128 attributeId, absent_days, 'AbsentDaysSecond'  
		from #students_secondary_calc

		union

		select studentNumber, 4129 attributeId, days_scheduled, 'ScheduleDaySecond'
		from #students_secondary_calc

	) x
inner join person p on p.studentNumber=x.studentNumber
inner join [identity] i on i.identityId=p.currentIdentityId
left join customStudent cs on cs.personId=p.personId and cs.attributeID=x.attributeId
where ISNULL(cs.value,'') <> x.value


------------------------------------------------------------------------------------
-- if student does not have the attribute, INSERT it.
------------------------------------------------------------------------------------
INSERT INTO customStudent (personId, attributeId, value, date, districtId)
select distinct i.personId, x.attributeId, x.value, cast(getDate() as smalldatetime), (select districtId from campusVersion)
-- select i.lastname, i.firstname, x.*, cs.*
from (
		select studentNumber, 4539 attributeId, school value, 'SecondarySchool' element
		from #students_secondary_calc

		union

		select studentNumber, 4127 attributeId, att_rate, 'ABPercentSecond'
		from #students_secondary_calc

		union

		select studentNumber, 4128 attributeId, absent_days, 'AbsentDaysSecond'  
		from #students_secondary_calc

		union

		select studentNumber, 4129 attributeId, days_scheduled, 'ScheduleDaySecond'
		from #students_secondary_calc

		union

		select studentNumber, 4132 attributeId, '1', 'CurrentTerm'
		from #students_secondary_calc

	) x
inner join person p on p.studentNumber=x.studentNumber
inner join [identity] i on i.identityId=p.currentIdentityId
left join customStudent cs on cs.personId=p.personId and cs.attributeID=x.attributeId
where cs.attributeId is null and x.value is not null
