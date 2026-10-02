# Data dictionary and sample flow

| Field | Analysis meaning | Source/handling |
|---|---|
| `date` | Calendar date, 2014-01-01 through 2020-12-31 | Parsed from `Painel.xlsx` DATE; daily complete calendar. |
| `ais` | Integrated Security Area, canonical `ais 01`--`ais 22` | Unicode/case normalized and zero-padded; non-geographic or missing labels excluded. |
| `city`, `unit` | Municipality/district name and AIS-qualified analysis-unit ID | Name normalization follows released code, including spelling repairs; AIS-qualified ID avoids cross-AIS collisions. |
| `total` | Number of victim records | Sum of `HOMICIDIOS` (one per source row). |
| `men` | Male victim count | `GENDER` in M, Masculino, MASCULINO, as in released code. |
| `women` | Residual count `total-men` | Mirrors released Stata code; includes 24 unclassified-sex records, so is not a strictly verified female count. |
| `crime_1`--`crime_4` | Released binary victim-record indicators summed to unit-day counts | Kept under source names because their coding meaning is not independently reclassified here. They need not be mutually exclusive. |
| `ExposureDistricts` | Gang-exposed district share in AIS | `Gang_Turfs.xlsx`; empirical 75th percentile 0.587728. AIS 07 is just above the numeric threshold but outside the paper's named top five. |
| `treat` | Main high-exposure AIS flag | 1 for 02, 06, 11, 12, 13; fixed over time. |
| `strike` | Strike-period flag | 1 from 2020-02-18 through 2020-03-01 inclusive. |
| `observed_source_row` | Whether a unit-day existed in the victim-record aggregation before balancing | `false` rows were inserted and set to zero for all seven outcomes. |

Source flow: 27,830 source victim rows; 412 excluded for absent/invalid AIS; 27,418 valid-AIS homicides; 21,891 observed valid unit-days; 358 units x 2,557 dates = 915,406 balanced unit-days, including 893,515 inserted zeros. The released intermediate DTA has 21,892 valid-AIS rows because one unit-day is split into two rows; after reaggregation it matches the 21,891 observed days from `Painel.xlsx` exactly. Seven exact repeated source rows are retained because identical attributes cannot establish that a homicide victim is duplicated. The main 84+13-day sample has 34,726 unit-days, of which 33,943 have zero total homicides, and 989 valid-AIS victim records. Within the 13 strike days there are 4,654 unit-days, 4,448 zeros, and 318 victim records. Of the 358 units, 94 are in the five treated AIS and 264 in the control AIS.
