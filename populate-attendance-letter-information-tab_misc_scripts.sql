/*******************
DMPS
Populate Attendance Letter Information tab

scripts/work

source = [desmoinesia.infinitecampus.org,7772].dev2.dbo.ch_MargiAttendance_tbl
destination: Student Information > General > Attendance Letter Information



********************/

select *
from [desmoinesia.infinitecampus.org,7772].dev2.dbo.Ch_mins_by_day_comp_20251



-- Look for dups
select personId, attributeId, count(attributeId) att_count
from dbo.customStudent
where attributeId IN (
						select attributeId
						from dbo.campusAttribute
						where object = 'Attendance Letter Information'
						)

group by personId, attributeId
having count(attributeId) >1


-- find and delete dups  (ran in SB & Prod 10/31)
drop table #dups
-- Attendance Letter Information duplicates (ghosted records)
select i.personId, i.lastname, i.firstname, cs.customId, ca.name attribute, cs.value, dup.att_count
into #dups
from customSTudent cs
inner join (-- 
				select personId, attributeId, count(attributeId) att_count
				from dbo.customStudent
				where attributeId IN (
										select attributeId
										from dbo.campusAttribute
										where object = 'Attendance Letter Information'
										)

				group by personId, attributeId
				having count(attributeId) >1
				) dup on dup.personId=cs.personId and dup.attributeId=cs.attributeId
inner join campusAttribute ca on ca.attributeId=cs.attributeId
inner join person p on p.personId=cs.personId
inner join [identity] i on i.identityId=p.currentIdentityId
order by cs.personid, cs.attributeId


delete from customStudent
where customID IN (
					select b.customId
					-- select *
					from #dups a
					inner join #dups b on b.personId=a.personId and b.attribute=a.attribute and b.value=a.value
					where b.customId > a.customId
					)


-- delete any NULL customStudent records for Attendance Letter Information (ran in SB & Prod 10/31)
delete
-- select *
from dbo.customStudent
where attributeId IN (
						select attributeId
						from dbo.campusAttribute
						where object = 'Attendance Letter Information'
						)
and value is null