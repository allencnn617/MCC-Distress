USE [BI]
GO

/****** Object:  StoredProcedure [MCC].[ClinicAudit_Data_DistressScreening]    Script Date: 9/9/2016 11:26:01 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/*************************************
General Information
-- Purpose:
-- Date:
-- Author:  Chris Burton
-- Source Systems:
-- Notes: 
-- Associated Tickets:
-- Business Contact:
-- Technical Contact: 
-- Informaticist:
-- Other Contacts:  

Change History
-- Version Number:
-- Author:  Connie Allen
-- Date: 5/16/2016
-- Purpose: return flowsheet data on the same chart but different visits
-- Description of Changes: changed join criteria to not use visit level criteria 
because users cannot easily tell what visit they are using when charting;
used the BI template format; read the CV3ClientDocument table only once for performance
-- Associated Tickets:  WO0000000010590
-- Business Contact:  Joan Scales
-- Technical Contact: 
-- Informaticist:
-- Other Contacts:  

-- Version Number:
-- Author:  Connie Allen
-- Date: 5/26/2016
-- Purpose: backed out changes from 5/16/16
-- Description of Changes: Joan said it was including data that should not be included
-- Associated Tickets:  WO0000000010590
-- Business Contact:  Joan Scales
-- Technical Contact: 
-- Informaticist:
-- Other Contacts:  

-- Version Number:
-- Author:  Connie Allen
-- Date: 5/31/2016
-- Purpose: revise join criteria for ArcType for 
-- Description of Changes: 
-- Associated Tickets:  WO0000000010590
-- Business Contact:  Joan Scales
-- Technical Contact: 
-- Informaticist:
-- Other Contacts:  

Approvals
-- Architecture Approval Date:
-- Architect:
-- Data Quality Approval Date:
-- Data Quality Specialist:
-- Data Specialist Approval Date: 
-- Data Specialist:
**************************************/

ALTER PROC [MCC].[ClinicAudit_Data_DistressScreening](@StartDate DATE, @EndDate DATE)



AS
--DECLARE  @StartDate DATE, @EndDate DATE
--SET @StartDate = '9/1/2015'
--SET @EndDate = '9/30/2015'


IF OBJECT_ID('tempdb..#MCCvisits') IS NOT NULL DROP TABLE #MCCvisits 


SELECT	
		cv.IDCode AS MedRecNum
		,cv.VisitIDCode AS VisitNumber
		,CONVERT(DATE,cv.AdmitDtm) AS AdmitDate
		,cv.ClientDisplayName AS Patient
		,edl.EDDisplayName AS CurrentLocation
		,l.Name
		,cv.TypeCode
		,cv.AdmitDtm DateofService
		,cv.ProviderDisplayName
		,sg.Description AS [Service]
		,subg.Description AS [ServiceSubGroup]
		,CASE 
					WHEN sg.Description = 'Medicine' THEN ' - Medical Oncology'
					WHEN sg.Description = 'Neurology' THEN ' - Neurology Oncology'
					WHEN subg.Description LIKE '%Otolaryngology%' THEN ' - Otolaryngology'
					WHEN sg.Description = 'Surgery' THEN ' - General Surgery'
					--WHEN subg.Description LIKE '%Otolaryngology%' THEN ' - Otolaryngology'
					WHEN sg.Description = 'Pediatrics' THEN ' - Pediatrics'
					WHEN subg.Description LIKE '%Transplant%' THEN ' - Transplant'
					--WHEN sg.Description  = 'Radiation Medicine' THEN ' - Radiation Medicine' 
					ELSE '' END AS [SubGroup]
		--,s.Description
		--,sg.Description
		--,subg.Description
		,cv.GUID AS ClientVisitGUID
		,cv.ChartGUID
		,cv.ClientGUID
		,cv.CareLevelCode
		--,cv.ArcType--5/31/16 revised
		,CASE
										WHEN cv.ArcType = 99
										THEN 0
										ELSE cv.ArcType
									END AS ArcType
INTO #MCCvisits
FROM SCMPROD1.dbo.CV3ClientVisit cv 
INNER JOIN SCMPROD1.dbo.CV3Location l ON cv.CurrentLocationGUID = l.GUID
	AND l.GUID IN (
					5000001020061001	--MCC-CBCC
					,2000001196061001	--MCC-Chemo 1
					,2000001325061001	--MCC-Chemo 2
					,1000001364061001	--MCC-Gyn/Onc
					,5000001149061001	--MCC-MHP
					,9000001020061001	--MCC-Multi D
					,4000001004061001)	--Pediatric HEM/ONC-Clinic)
	AND cv.AdmitDtm BETWEEN @StartDate AND DATEADD(DAY,1,@EndDate)--DATEADD(WEEK,-1,CONVERT(DATE,GETDATE()))  AND CONVERT(DATE,GETDATE())--CONVERT(DATE,GETDATE())
	AND cv.TypeCode = 'Outpatient'
--	AND cv.CareLevelCode = 'MedicalOncology'
	AND cv.VisitStatus <> 'CAN'
	--AND cv.VisitIDCode NOT LIKE '3-%'
INNER JOIN [SCMPROD1].[dbo].[SXAEDLocation] edl ON edl.LocationGUID = l.GUID
INNER JOIN SCMPROD1.dbo.[CV3Service] s ON s.GUID = cv.ServiceGUID
LEFT JOIN SCMPROD1.dbo.[CV3ServiceGroup] sg ON sg.Code = s.GroupCode
LEFT JOIN SCMPROD1.dbo.[CV3ServiceSubGroup] subg ON s.SubGroupCode = subg.Code
AND sg.Description  <> 'Radiation Medicine'
--WHERE cv.IDCode = '013731195'--sg.Description NOT IN ('Obstetrics/Gynecology','Medicine','Pediatrics','Breast Care Center','Surgery')

--SELECT * FROM #MCCvisits WHERE MedRecNum = '013731195'



IF OBJECT_ID('tempdb..#stresslvl') IS NOT NULL DROP TABLE #stresslvl
SELECT DISTINCT v.Patient
	,v.MedRecNum
	,v.VisitNumber
	,v.CurrentLocation
	,v.SubGroup
	,cd.DocumentName
	,cd.CreatedWhen
	,fs.Value AS StressLvl
INTO #stresslvl
FROM  #MCCVisits v
INNER JOIN SCMPROD1.dbo.CV3ClientDocument cd
ON cd.ClientVisitGUID = v.ClientVisitGUID --visit level
AND cd.ClientGUID = v.ClientGUID
--AND cd.CreatedWhen BETWEEN v.FirstEncounteroftheMonth /*DATEADD(DAY,-45,v.AdmitDate)*/ AND DATEADD(DAY,1,v.LastEncounteroftheMonth)
AND cd.DocumentName = 'Oncology Clinic Record'
--AND cd.ArcType = v.ArcType
INNER JOIN SCMPROD1.dbo.CV3ObservationDocument od 
ON cd.GUID = od.OwnerGUID
AND od.ObsMasterItemGUID = 9000020626702890 --Stress Level
INNER JOIN SCMPROD1.dbo.SCMObsFSListValues fs 
ON fs.ParentGUID = od.ObservationDocumentGUID
AND fs.ClientGUID = v.ClientGUID
ORDER BY v.Patient

IF OBJECT_ID('tempdb..#stresslvlCNTRPT') IS NOT NULL DROP TABLE #stresslvlCNTRPT
SELECT MedRecNum
	,COUNT(StressLvl) StresslvlCountReport
INTO #stresslvlCNTRPT
FROM #stresslvl
GROUP BY MedRecNum
ORDER BY COUNT(StressLvl) DESC

IF OBJECT_ID('tempdb..#MCCFirstScreenVisit') IS NOT NULL DROP TABLE #MCCFirstScreenVisit
SELECT DISTINCT
		m.MedRecNum
		,(SELECT TOP 1 m2.CurrentLocation FROM #stresslvl m2 WHERE m2.MedRecNum = m.MedRecNum  ORDER BY m2.VisitNumber) AS FirstEncounterClinic
		,(SELECT TOP 1 m2.SubGroup FROM #stresslvl m2 WHERE m2.MedRecNum = m.MedRecNum  ORDER BY m2.VisitNumber) AS FirstEncounterSpecialty
		,(SELECT TOP 1 m2.StressLvl FROM #stresslvl m2 WHERE m2.MedRecNum = m.MedRecNum  ORDER BY m2.VisitNumber) AS FirstScreen
	--	,(SELECT TOP 1 m2.CareLevelCode FROM #MCCvisits m2 WHERE m2.MedRecNum = m.MedRecNum  ORDER BY m2.VisitNumber) AS FirstEncounterCareLevelCode
	--	,(SELECT TOP 1 m2.TypeCode FROM #MCCvisits m2 WHERE m2.MedRecNum = m.MedRecNum  ORDER BY m2.VisitNumber) AS FirstEncounterTypeCode
INTO #MCCFirstScreenVisit
FROM #MCCvisits m 
--SELECT * FROM #MCCFirstScreenVisit WHERE MedRecNum = '010319036'

--SELECT * FROM #MCCFirstScreenVisit WHERE FirstEncounterClinic = 'MCC 1st FL Infusion Services'

IF OBJECT_ID('tempdb..#stresslvlCNT') IS NOT NULL DROP TABLE #stresslvlCNT
SELECT 
	cv.MedRecNum
	,COUNT(fs.Value) AS StressLvlCNT
INTO #stresslvlCNT
FROM   SCMPROD1.dbo.CV3ClientVisit v
INNER JOIN #MCCvisits cv ON v.ClientGUID= cv.ClientGUID
AND v.CurrentLocationGUID IN (
					5000001020061001	--MCC-CBCC
					,2000001196061001	--MCC-Chemo 1
					,2000001325061001	--MCC-Chemo 2
					,1000001364061001	--MCC-Gyn/Onc
					,5000001149061001	--MCC-MHP
					,9000001020061001	--MCC-Multi D
					,4000001004061001)	--Pediatric HEM/ONC-Clinic)
AND v.TypeCode = 'Outpatient'
--	AND cv.CareLevelCode = 'MedicalOncology'
	AND v.VisitStatus <> 'CAN'
AND v.AdmitDtm BETWEEN DATEADD(DAY,-45,cv.Admitdate) AND DATEADD(DAY,1,cv.Admitdate)
INNER JOIN SCMPROD1.dbo.CV3ClientDocument cd
ON cd.ClientGUID = v.ClientGUID
AND cd.ClientVisitGUID = v.GUID
--AND cd.CreatedWhen BETWEEN DATEADD(DAY,-45,cv.Admitdate) AND DATEADD(DAY,1,cv.Admitdate)
AND cd.DocumentName = 'Oncology Clinic Record'
--AND cd.ArcType = v.ArcType
INNER JOIN SCMPROD1.dbo.CV3ObservationDocument od 
ON cd.GUID = od.OwnerGUID
AND od.ObsMasterItemGUID = 9000020626702890 --Stress Level
INNER JOIN SCMPROD1.dbo.SCMObsFSListValues fs 
ON fs.ParentGUID = od.ObservationDocumentGUID
AND fs.ClientGUID = v.ClientGUID
--AND fs.CreatedWhen BETWEEN cv.AdmitDate AND DATEADD(DAY,1,cv.AdmitDate)
--ORDER BY VisitNumber
GROUP BY cv.MedRecNum
--SELECT * FROM #stresslvlCNT WHERE MedRecNum = '013731195'


IF OBJECT_ID('tempdb..#stresspractprob') IS NOT NULL DROP TABLE #stresspractprob
SELECT DISTINCT v.Patient
	,v.MedRecNum
	,v.VisitNumber
	,v.CurrentLocation
	,v.SubGroup
	,fs.Value AS Problem
INTO #stresspractprob
FROM  #MCCVisits v
INNER JOIN SCMPROD1.dbo.CV3ClientDocument cd
ON cd.ClientVisitGUID = v.ClientVisitGUID --visit level
AND cd.ClientGUID = v.ClientGUID
--AND cd.CreatedWhen BETWEEN v.FirstEncounteroftheMonth /*DATEADD(DAY,-45,v.AdmitDate)*/ AND DATEADD(DAY,1,v.LastEncounteroftheMonth)
AND cd.DocumentName = 'Oncology Clinic Record'
--AND cd.ArcType = v.ArcType
INNER JOIN SCMPROD1.dbo.CV3ObservationDocument od 
ON cd.GUID = od.OwnerGUID
AND od.ObsMasterItemGUID = 9000020627102890 --uk onc par pract prob rd Practical Problems
INNER JOIN SCMPROD1.dbo.SCMObsFSListValues fs 
ON fs.ParentGUID = od.ObservationDocumentGUID
AND fs.ClientGUID = v.ClientGUID
ORDER BY v.Patient

--SELECT * FROM #stresspractprob WHERE VisitNumber = '003958147-5243'

IF OBJECT_ID('tempdb..#stresspractprobpivot') IS NOT NULL DROP TABLE #stresspractprobpivot
SELECT Patient
		,MedRecNum
		,VisitNumber
		,CurrentLocation
		,SubGroup
		,[child care]+[treatment decisions]+[work/school]+[transportation]+[insurance/financial]+[housing] AS [Practical Problems]
		,[child care] AS [Practical Problem - child care]
		,[housing] AS [Practical Problem - housing]
		,[insurance/financial] AS [Practical Problem - insurance/financial]
		,[transportation] AS [Practical Problem - transportation]
		,[work/school] AS [Practical Problem - work/school] 
		,[treatment decisions] AS [Practical Problem - treatment decisions]	
INTO #stresspractprobpivot
FROM #stresspractprob
PIVOT
(COUNT(Problem) FOR Problem IN ([child care]
								,[housing]
								,[insurance/financial]
								,[transportation]
								,[work/school]
								,[treatment decisions]
								)) AS PivotTable


IF OBJECT_ID('tempdb..#stressfamprob') IS NOT NULL DROP TABLE #stressfamprob
SELECT DISTINCT v.Patient
	,v.MedRecNum
	,v.VisitNumber
	,v.CurrentLocation
	,v.SubGroup
	,fs.Value AS Problem
INTO #stressfamprob
FROM  #MCCVisits v
INNER JOIN SCMPROD1.dbo.CV3ClientDocument cd
ON cd.ClientVisitGUID = v.ClientVisitGUID --visit level
AND cd.ClientGUID = v.ClientGUID
AND cd.DocumentName = 'Oncology Clinic Record'
--AND cd.ArcType = v.ArcType
INNER JOIN SCMPROD1.dbo.CV3ObservationDocument od 
ON cd.GUID = od.OwnerGUID
AND od.ObsMasterItemGUID = 9000020627502890 --uk onc par fam prob rd Family Problems
INNER JOIN SCMPROD1.dbo.SCMObsFSListValues fs 
ON fs.ParentGUID = od.ObservationDocumentGUID
AND fs.ClientGUID = v.ClientGUID
ORDER BY v.Patient

--SELECT * FROM #stressfamprob

IF OBJECT_ID('tempdb..#stressfamprobpivot') IS NOT NULL DROP TABLE #stressfamprobpivot
SELECT Patient
		,MedRecNum
		,VisitNumber
		,CurrentLocation
		,SubGroup
		,[dealing with children]+[dealing with partner]+[ability to have children]+[family health issues]  AS [Family Problems]
		,[dealing with children] AS [Family Problem - dealing with children]
		,[dealing with partner] AS [Family Problem - dealing with partner]
		,[ability to have children] AS [Family Problem - ability to have children]
		,[family health issues] AS [Family Problem - family health issues]
INTO #stressfamprobpivot
FROM #stressfamprob
PIVOT
(COUNT(Problem) FOR Problem IN ([dealing with children]
								,[dealing with partner]
								,[ability to have children]
								,[family health issues])) AS PivotTable
--SELECT DISTINCT Problem FROM #stressfamprob

IF OBJECT_ID('tempdb..#stressemoprob') IS NOT NULL DROP TABLE #stressemoprob
SELECT DISTINCT v.Patient
	,v.MedRecNum
	,v.VisitNumber
	,v.CurrentLocation
	,v.SubGroup
	,fs.Value AS Problem
INTO #stressemoprob
FROM  #MCCVisits v
INNER JOIN SCMPROD1.dbo.CV3ClientDocument cd
ON cd.ClientVisitGUID = v.ClientVisitGUID --visit level
AND cd.ClientGUID = v.ClientGUID
--AND cd.CreatedWhen BETWEEN v.FirstEncounteroftheMonth /*DATEADD(DAY,-45,v.AdmitDate)*/ AND DATEADD(DAY,1,v.LastEncounteroftheMonth)
AND cd.DocumentName = 'Oncology Clinic Record'
--AND cd.ArcType = v.ArcType
INNER JOIN SCMPROD1.dbo.CV3ObservationDocument od 
ON cd.GUID = od.OwnerGUID
AND od.ObsMasterItemGUID = 9000020627702890 --uk onc par emo prob rd Emotional Problems
INNER JOIN SCMPROD1.dbo.SCMObsFSListValues fs 
ON fs.ParentGUID = od.ObservationDocumentGUID
AND fs.ClientGUID = v.ClientGUID
ORDER BY v.Patient

--SELECT * FROM #stressemoprob WHERE VisitNumber = '003069234-5133'


IF OBJECT_ID('tempdb..#stressemoprobpivot') IS NOT NULL DROP TABLE #stressemoprobpivot
SELECT Patient
		,MedRecNum
		,VisitNumber
		,CurrentLocation
		,SubGroup
		,[depression]+[fears]+[nervousness]+[sadness]+[worry]+[loss of interest in usual activities] AS [Emotional Problems]
		,[depression] AS [Emotional Problem - depression]
		,[fears] AS [Emotional Problem - fears]
		,[loss of interest in usual activities] AS [Emotional Problem - loss of interest in usual activities]
		,[nervousness] AS [Emotional Problem - nervousness]
		,[sadness] AS [Emotional Problem - sadness]
		,[worry] AS [Emotional Problem - worry]
		,[spiritual/religious concerns] AS [Spiritual Problems - spiritual/religious concerns]
INTO #stressemoprobpivot
FROM #stressemoprob 
PIVOT
(COUNT(Problem) FOR Problem IN ([depression]
								,[fears]
								,[nervousness]
								,[sadness]
								,[worry]
								,[loss of interest in usual activities]
								,[spiritual/religious concerns])) AS PivotTable

IF OBJECT_ID('tempdb..#stressphysprob') IS NOT NULL DROP TABLE #stressphysprob
SELECT DISTINCT v.Patient
	,v.MedRecNum
	,v.VisitNumber
	,v.CurrentLocation
	,v.SubGroup
	,fs.Value AS Problem
INTO #stressphysprob
FROM  #MCCVisits v
INNER JOIN SCMPROD1.dbo.CV3ClientDocument cd
ON cd.ClientVisitGUID = v.ClientVisitGUID --visit level
AND cd.ClientGUID = v.ClientGUID
AND cd.ChartGUID = v.ChartGUID
AND cd.ArcType = v.ArcType
INNER JOIN SCMPROD1.dbo.CV3ObservationDocument od 
ON cd.GUID = od.OwnerGUID
AND od.ObsMasterItemGUID = 9000020627302890 --uk onc par phys prob rd Physical Problems
INNER JOIN SCMPROD1.dbo.SCMObsFSListValues fs 
ON fs.ParentGUID = od.ObservationDocumentGUID
AND fs.ClientGUID = v.ClientGUID
ORDER BY v.Patient

--SELECT * FROM #stressphysprob WHERE VisitNumber = '003069234-5133'

IF OBJECT_ID('tempdb..#stressphysprobpivot') IS NOT NULL DROP TABLE #stressphysprobpivot
SELECT  Patient
		,MedRecNum
		,VisitNumber
		,CurrentLocation
		,SubGroup
		,[appearance]+[bathing/dressing]+[breathing]+[changes in urination]+[constipation]+[diarrhea]
			+[eating]+[fatigue]+[feeling swollen]+[fevers]+[getting around]+[indigestion]+[memory/concentration]
			+[mouth sores]+[nausea]+[nose dry/congestion]+[pain]+[sexual]+[skin dry/itchy]+[sleep]
			+[substance abuse]+[tingling in hands/feet]+[weight loss/gain] AS [Physical Problems]
		,[appearance] AS [Physical Problem - appearance]
		,[bathing/dressing] AS [Physical Problem - bathing/dressing]
		,[breathing] AS [Physical Problem - breathing]
		,[changes in urination] AS [Physical Problem - changes in urination]
		,[constipation] AS [Physical Problem - constipation]
		,[diarrhea] AS [Physical Problem - diarrhea]
		,[eating] AS [Physical Problem - eating]
		,[fatigue] AS [Physical Problem - fatigue]
		,[feeling swollen] AS [Physical Problem - feeling swollen]
		,[fevers] AS [Physical Problem - fevers]
		,[getting around] AS [Physical Problem - getting around]
		,[indigestion] AS [Physical Problem - indigestion]
		,[memory/concentration] AS [Physical Problem - memory/concentration]
		,[mouth sores] AS [Physical Problem - mouth sores]
		,[nausea] AS [Physical Problem - nausea]
		,[nose dry/congestion] AS [Physical Problem - nose dry/congestion]
		,[pain] AS [Physical Problem - pain]
		,[sexual] AS [Physical Problem - sexual]
		,[skin dry/itchy] AS [Physical Problem - skin dry/itchy]
		,[sleep] AS [Physical Problem - sleep]
		,[substance abuse] AS [Physical Problem - substance abuse]
		,[tingling in hands/feet] AS [Physical Problem - tingling in hands/feet]
		,[weight loss/gain] AS [Physical Problem - weight loss/gain]
INTO #stressphysprobpivot
FROM #stressphysprob
PIVOT
(COUNT(Problem) FOR Problem IN ([appearance]
								,[substance abuse]
								,[constipation]
								,[diarrhea]
								,[weight loss/gain]
								,[eating]
								,[indigestion]
								,[bathing/dressing]
								,[getting around]
								,[breathing]
								,[changes in urination]
								,[fatigue]
								,[feeling swollen]
								,[fevers]
								,[memory/concentration]
								,[mouth sores]
								,[nausea]
								,[nose dry/congestion]
								,[pain]
								,[sexual]
								,[skin dry/itchy]
								,[sleep]
								,[tingling in hands/feet])) AS PivotTable

--SELECT DISTINCT Problem FROM #stressphysprob


--SELECT * FROM #stresslvl

IF OBJECT_ID('tempdb..#stress45') IS NOT NULL DROP TABLE #stress45
SELECT DISTINCT v.Patient
	,v.MedRecNum
	,v.VisitNumber
	,v.CurrentLocation
	,v.SubGroup
	,MAX(CASE fs.Value	WHEN 'Yes' THEN 1 
					WHEN 'No' THEN 0
					ELSE fs.Value END) AS ScreenedInLast45Days
INTO #stress45
FROM  #MCCVisits v
INNER JOIN SCMPROD1.dbo.CV3ClientDocument cd
ON cd.ClientVisitGUID = v.ClientVisitGUID --visit level
AND cd.ClientGUID = v.ClientGUID
AND cd.DocumentName = 'Oncology Clinic Record'
--AND cd.ArcType = v.ArcType
INNER JOIN SCMPROD1.dbo.CV3ObservationDocument od 
ON cd.GUID = od.OwnerGUID
AND od.ObsMasterItemGUID = 9000020628102890 --Has the distress screening been completed in the last 45 days?
INNER JOIN SCMPROD1.dbo.SCMObsFSListValues fs 
ON fs.ParentGUID = od.ObservationDocumentGUID
AND fs.ClientGUID = v.ClientGUID
GROUP BY v.Patient
	,v.MedRecNum
	,v.VisitNumber
	,v.CurrentLocation
	,v.SubGroup
ORDER BY v.Patient

--SELECT * FROM #stress45 WHERE VisitNumber = '003069234-5133'
IF OBJECT_ID('tempdb..#stresscomment') IS NOT NULL DROP TABLE #stresscomment
SELECT DISTINCT v.Patient
	,v.MedRecNum
	,v.VisitNumber
	,v.CurrentLocation
	,v.SubGroup
	,cd.DocumentName
	,cd.CreatedWhen
	,o.ValueText
INTO #stresscomment
FROM  #MCCVisits v
INNER JOIN SCMPROD1.dbo.CV3ClientDocument cd
ON cd.ClientVisitGUID = v.ClientVisitGUID --visit level
AND cd.ClientGUID = v.ClientGUID
AND cd.ChartGUID = v.ChartGUID
AND cd.ArcType = v.ArcType
INNER JOIN SCMPROD1.dbo.CV3ObservationDocument od 
ON cd.GUID = od.OwnerGUID
AND od.ObsMasterItemGUID = 9000020700402890	--onc uk distress screen  ft
INNER JOIN SCMPROD1.dbo.CV3Observation o 
ON o.GUID = od.ObservationGUID
ORDER BY v.Patient

--SELECT * FROM #stresscomment WHERE VisitNumber = '003069234-5133'

IF OBJECT_ID('tempdb..#stressrfd') IS NOT NULL DROP TABLE #stressrfd
SELECT DISTINCT v.Patient
	,v.MedRecNum
	,v.VisitNumber
	,v.CurrentLocation
	,v.SubGroup
	--,cd.DocumentName
	--,cd.CreatedWhen
	,CASE fs.Value	WHEN 'Yes' THEN 1 
					WHEN 'No' THEN 0
					ELSE fs.Value END AS StressRefused
INTO #stressrfd
FROM  #MCCVisits v
INNER JOIN SCMPROD1.dbo.CV3ClientDocument cd
ON cd.ClientVisitGUID = v.ClientVisitGUID --visit level
AND cd.ClientGUID = v.ClientGUID
AND cd.DocumentName = 'Oncology Clinic Record'
--AND cd.ArcType = v.ArcType
INNER JOIN SCMPROD1.dbo.CV3ObservationDocument od 
ON cd.GUID = od.OwnerGUID
AND od.ObsMasterItemGUID = 9000020700202890 --Patient declined screening participation
INNER JOIN SCMPROD1.dbo.SCMObsFSListValues fs 
ON fs.ParentGUID = od.ObservationDocumentGUID
AND fs.ClientGUID = v.ClientGUID
ORDER BY v.Patient

--SELECT * FROM #stressrfd

IF OBJECT_ID('tempdb..#stressrfdr') IS NOT NULL DROP TABLE #stressrfdr
SELECT DISTINCT v.Patient
	,v.MedRecNum
	,v.VisitNumber
	,v.CurrentLocation
	,v.Service
	,v.SubGroup
	,v.DateofService
	,v.TypeCode
	,v.CareLevelCode
	,lv.StressLvl
	,lvcnt.StressLvlCNT
	,CASE WHEN lvcnt.StressLvlCNT > 0 OR l.ScreenedInLast45Days = 1 OR r.StressRefused = 1 OR StressLvl IS NOT NULL
			THEN 1 ELSE 0 END AS ScreenedInLast45DaysCalc
	,slcr.StresslvlCountReport
	,pp.[Practical Problems]
	,pp.[Practical Problem - child care]
	,pp.[Practical Problem - housing]
	,pp.[Practical Problem - insurance/financial]
	,pp.[Practical Problem - transportation]
	,pp.[Practical Problem - work/school]
	,pp.[Practical Problem - treatment decisions]
	,fp.[Family Problems]
	,fp.[Family Problem - dealing with children]
	,fp.[Family Problem - dealing with partner]
	,fp.[Family Problem - ability to have children]
	,fp.[Family Problem - family health issues]
	,ep.[Emotional Problems]
	,ep.[Emotional Problem - depression]
	,ep.[Emotional Problem - fears]
	,ep.[Emotional Problem - nervousness]
	,ep.[Emotional Problem - sadness]
	,ep.[Emotional Problem - worry]
	,ep.[Emotional Problem - loss of interest in usual activities]
	,ep.[Spiritual Problems - spiritual/religious concerns]
	,php.[Physical Problems]
	,php.[Physical Problem - appearance]
	,php.[Physical Problem - substance abuse]
	,php.[Physical Problem - constipation]
	,php.[Physical Problem - diarrhea]
	,php.[Physical Problem - weight loss/gain]
	,php.[Physical Problem - eating]
	,php.[Physical Problem - indigestion]
	,php.[Physical Problem - bathing/dressing]
	,php.[Physical Problem - getting around]
	,php.[Physical Problem - breathing]
	,php.[Physical Problem - changes in urination]
	,php.[Physical Problem - fatigue]
	,php.[Physical Problem - feeling swollen]
	,php.[Physical Problem - fevers]
	,php.[Physical Problem - memory/concentration]
	,php.[Physical Problem - mouth sores]
	,php.[Physical Problem - nausea]
	,php.[Physical Problem - nose dry/congestion]
	,php.[Physical Problem - pain]
	,php.[Physical Problem - sexual]
	,php.[Physical Problem - skin dry/itchy]
	,php.[Physical Problem - sleep]
	,php.[Physical Problem - tingling in hands/feet]
	,c.ValueText AS [Distress Screening Comment]
	,CASE WHEN c.ValueText IS NOT NULL THEN 1 ELSE 0 END AS [DistressScreeningCommented]
	,CASE WHEN c.ValueText IS NOT NULL 
				AND (pp.[Practical Problems] = 0 OR pp.[Practical Problems] IS NULL)
				AND (fp.[Family Problems] = 0 OR fp.[Family Problems] IS NULL)
				AND (ep.[Emotional Problems] = 0 OR ep.[Emotional Problems] IS NULL)
				AND (ep.[Spiritual Problems - spiritual/religious concerns] = 0 OR ep.[Spiritual Problems - spiritual/religious concerns] IS NULL)
				AND (php.[Physical Problems] = 0 OR php.[Physical Problems] IS NULL)
	THEN 1 ELSE 0 END AS [DistressCommentW/OProblem]
	,l.ScreenedInLast45Days AS ScreenedInLast45Days
	,r.StressRefused AS StressRefused
	,fsv.FirstEncounterClinic
	,fsv.FirstEncounterSpecialty
	,fsv.FirstScreen
	INTO #stressrfdr
	 FROM #MCCVisits v
LEFT JOIN #stresslvl lv ON lv.VisitNumber = v.VisitNumber
LEFT JOIN #stress45 l ON l.VisitNumber = v.VisitNumber  
LEFT JOIN #stressrfd r ON r.VisitNumber = v.VisitNumber
LEFT JOIN #stresspractprobpivot pp ON pp.VisitNumber = v.VisitNumber
LEFT JOIN #stressfamprobpivot fp ON fp.VisitNumber = v.VisitNumber
LEFT JOIN #stressemoprobpivot ep ON ep.VisitNumber = v.VisitNumber
LEFT JOIN #stressphysprobpivot php ON php.VisitNumber = v.VisitNumber 
LEFT JOIN #stresscomment c ON c.VisitNumber = v.VisitNumber
LEFT JOIN #MCCFirstScreenVisit fsv ON fsv.MedRecNum = v.MedRecNum AND fsv.FirstEncounterClinic = v.CurrentLocation-- AND fsv.FirstEncounterSpecialty = v.SubGroup
LEFT JOIN #stresslvlcnt lvcnt ON lvcnt.MedRecNum = v.MedRecNum
LEFT JOIN #stresslvlCNTRPT slcr ON slcr.MedRecNum = v.MedRecNum AND StresslvlCountReport > 0
--GROUP BY v.Patient
--	,v.MedRecNum
--	,v.VisitNumber
--	,v.CurrentLocation
--	,v.Service
--	,v.SubGroup
--	,v.DateofService
--	,v.TypeCode
--	,lv.StressLvl
--	,pp.[Practical Problems]
--	,pp.[Practical Problem - child care]
--	,pp.[Practical Problem - housing]
--	,pp.[Practical Problem - insurance/financial]
--	,pp.[Practical Problem - transportation]
--	,pp.[Practical Problem - work/school]
--	,pp.[Practical Problem - treatment decisions]
--	,fp.[Family Problems]
--	,fp.[Family Problem - dealing with children]
--	,fp.[Family Problem - dealing with partner]
--	,fp.[Family Problem - ability to have children]
--	,fp.[Family Problem - family health issues]
--	,ep.[Emotional Problems]
--	,ep.[Emotional Problem - depression]
--	,ep.[Emotional Problem - fears]
--	,ep.[Emotional Problem - nervousness]
--	,ep.[Emotional Problem - sadness]
--	,ep.[Emotional Problem - worry]
--	,ep.[Emotional Problem - loss of interest in usual activities]
--	,ep.[Spiritual Problems - spiritual/religious concerns]
--	,php.[Physical Problems]
--	,php.[Physical Problem - appearance]
--	,php.[Physical Problem - substance abuse]
--	,php.[Physical Problem - constipation]
--	,php.[Physical Problem - diarrhea]
--	,php.[Physical Problem - weight loss/gain]
--	,php.[Physical Problem - eating]
--	,php.[Physical Problem - indigestion]
--	,php.[Physical Problem - bathing/dressing]
--	,php.[Physical Problem - getting around]
--	,php.[Physical Problem - breathing]
--	,php.[Physical Problem - changes in urination]
--	,php.[Physical Problem - fatigue]
--	,php.[Physical Problem - feeling swollen]
--	,php.[Physical Problem - fevers]
--	,php.[Physical Problem - memory/concentration]
--	,php.[Physical Problem - mouth sores]
--	,php.[Physical Problem - nausea]
--	,php.[Physical Problem - nose dry/congestion]
--	,php.[Physical Problem - pain]
--	,php.[Physical Problem - sexual]
--	,php.[Physical Problem - skin dry/itchy]
--	,php.[Physical Problem - sleep]
--	,php.[Physical Problem - tingling in hands/feet]
--	,c.ValueText
ORDER BY Patient

--SELECT DISTINCT Problem FROM #stressfamprob
--SELECT * FROM #stress45 WHERE VisitNumber = '021358668-5134'
--SELECT * FROM #stressrfdr WHERE StresslvlCountReport IS NOT NULL

SELECT 
	v.Patient
	,v.MedRecNum
	,v.VisitNumber
	,v.DateofService
	,v.ProviderDisplayName
	,CASE	WHEN v.CurrentLocation = 'MCC MultiD Clinic' THEN v.CurrentLocation + v.SubGroup
			ELSE v.CurrentLocation END AS CurrentLocation
	,CASE	WHEN s.FirstEncounterClinic IS NULL AND v.CurrentLocation = 'MCC MultiD Clinic' THEN v.CurrentLocation + v.SubGroup
			WHEN s.FirstEncounterClinic IS NULL AND v.CurrentLocation <> 'MCC MultiD Clinic' THEN v.CurrentLocation
			WHEN s.FirstEncounterClinic= 'MCC MultiD Clinic' THEN s.FirstEncounterClinic + s.FirstEncounterSpecialty
			ELSE s.FirstEncounterClinic END AS FirstScreenLocation
	,v.Service
	,v.ServiceSubGroup
	,v.SubGroup AS Specailty
	,v.TypeCode AS TypeCode
	,v.CareLevelCode
	,s.StressLvl
	,s.FirstScreen
	,s.StressRefused
	,s.ScreenedInLast45Days
	,s.StressLvlCNT
	,CASE WHEN COALESCE(s.ScreenedInLast45DaysCalc,0) = 0 AND s.StressLvl IS NULL THEN 1
		ELSE 0 END AS ScreenMissed
	,COALESCE(s.ScreenedInLast45DaysCalc,0) AS ScreenedInLast45DaysCalc
	,CASE WHEN StresslvlCountReport > 1  AND s.FirstScreen IS NOT NULL THEN 1 ELSE NULL END AS MultipleScreens
	,s.[Practical Problems]
	,s.[Practical Problem - child care]
	,s.[Practical Problem - housing]
	,s.[Practical Problem - insurance/financial]
	,s.[Practical Problem - transportation]
	,s.[Practical Problem - work/school]
	,s.[Practical Problem - treatment decisions]
	,s.[Family Problems]
	,s.[Family Problem - dealing with children]
	,s.[Family Problem - dealing with partner]
	,s.[Family Problem - ability to have children]
	,s.[Family Problem - family health issues]
	,s.[Emotional Problems]
	,s.[Emotional Problem - depression]
	,s.[Emotional Problem - fears]
	,s.[Emotional Problem - nervousness]
	,s.[Emotional Problem - sadness]
	,s.[Emotional Problem - worry]
	,s.[Emotional Problem - loss of interest in usual activities]
	,s.[Spiritual Problems - spiritual/religious concerns]
	,s.[Physical Problems]
	,s.[Physical Problem - appearance]
	,s.[Physical Problem - substance abuse]
	,s.[Physical Problem - constipation]
	,s.[Physical Problem - diarrhea]
	,s.[Physical Problem - weight loss/gain]
	,s.[Physical Problem - eating]
	,s.[Physical Problem - indigestion]
	,s.[Physical Problem - bathing/dressing]
	,s.[Physical Problem - getting around]
	,s.[Physical Problem - breathing]
	,s.[Physical Problem - changes in urination]
	,s.[Physical Problem - fatigue]
	,s.[Physical Problem - feeling swollen]
	,s.[Physical Problem - fevers]
	,s.[Physical Problem - memory/concentration]
	,s.[Physical Problem - mouth sores]
	,s.[Physical Problem - nausea]
	,s.[Physical Problem - nose dry/congestion]
	,s.[Physical Problem - pain]
	,s.[Physical Problem - sexual]
	,s.[Physical Problem - skin dry/itchy]
	,s.[Physical Problem - sleep]
	,s.[Physical Problem - tingling in hands/feet]
	,s.DistressScreeningCommented
	,s.[Distress Screening Comment]
	,s.[DistressCommentW/OProblem]
	
	,CASE WHEN FirstScreen BETWEEN 0 AND 4 THEN 1
		WHEN FirstScreen IS NULL THEN NULL
		ELSE 0 END AS [Stresslvl 0-4]
	,CASE WHEN FirstScreen BETWEEN 5 AND 8 THEN 1
		WHEN FirstScreen IS NULL THEN NULL
		ELSE 0 END AS [Stresslvl 5-8]
	,CASE WHEN FirstScreen BETWEEN 9 AND 10 THEN 1
		WHEN FirstScreen IS NULL THEN NULL
		ELSE 0 END AS [Stresslvl 9-10]
	,CASE WHEN FirstScreen IS NOT NULL
		--OR ScreenedInLast45Days = 1
		--OR StressRefused = 1
		THEN 1
		ELSE 0 END AS StressScreenCompleted
FROM #stressrfdr s
RIGHT JOIN #MCCvisits v ON s.VisitNumber =v.VisitNumber --WHERE v.MedRecNum = '013731195'--v.CurrentLocation = 'MCC 1st FL Infusion Services'

--ORDER BY Patient
--WHERE COALESCE(s.ScreenedInLast45DaysCalc,0) = 0
--		 ORDER BY Patient
--INNER JOIN TimeSeries ts ON ts.Date = s.DateofService 

--IF OBJECT_ID('tempdb..#pivot') IS NOT NULL DROP TABLE #pivot
--SELECT
--rv.MedRecNum
--,rv.VisitNumber
--,rv.CurrentLocation
--,rv.SubGroup
--,ss.Name
--,'N/A'
--,ss.CreatedWhen
--,16 AS QOrder
--,'Have Distress Screening orders been entered?' as Question
--,COALESCE(ss.StressScreenCompleted,0) AS Checked 
--INTO #pivot  
--FROM #MCCvisits rv
--LEFT JOIN #stressrfdr ss ON rv.VisitNumber = ss.VisitNumber


GO

