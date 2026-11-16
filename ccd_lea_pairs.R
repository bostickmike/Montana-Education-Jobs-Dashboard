# Montana's elementary + high school district pairs in CCD's own names: which
# CCD district records make up each combined registry district ("Billings
# Public Schools" = "Billings Elem" + "Billings H S"). Input to
# build_mt_district_crosswalk() (opi_reconcile.R), which turns the pairs into
# each registry district's LEAIDs in mt_district_crosswalk.csv; every federal
# fetch then goes by those ids (edjobs fetch_ccd_teacher_fte(),
# fetch_census_saipe_child_poverty(); package phase 5, 2026-11-15, when the
# CCD and SAIPE fetch code in ccd_staff_scraper.R / census_saipe_scraper.R
# moved to edjobs).
#
# Hand-maintained: some high school districts are named after their town
# ("Billings H S"), others after their county ("Fergus H S" is Lewistown's,
# "Flathead H S" Kalispell's, "Park H S" Livingston's), so no name rule pairs
# them. Confirmed against the live CCD directory (2026-08-06 and 08-07). A
# few are one unified K-12 record (East Helena, Lockwood, Hamilton).

MT_CCD_LEA_MAP <- list(
  "Billings Public Schools" = c("Billings Elem", "Billings H S"),
  "Missoula County Public Schools" = c("Missoula Elem", "Missoula H S"),
  "Great Falls Public Schools" = c("Great Falls Elem", "Great Falls H S"),
  "Bozeman Public Schools" = c("Bozeman Elem", "Bozeman H S"),
  "Helena Public Schools" = c("Helena Elem", "Helena H S"),
  "Butte School District 1" = c("Butte Elem", "Butte H S"),
  "Belgrade School District 44" = c("Belgrade Elem", "Belgrade H S"),
  "East Helena Public Schools" = c("East Helena K-12"),
  "Lockwood Schools" = c("Lockwood K-12"),
  "Hamilton School District 3" = c("Hamilton K-12 Schools"),
  "Havre Public Schools" = c("Havre Elem", "Havre H S"),
  "Whitefish School District" = c("Whitefish Elem", "Whitefish H S"),
  "Columbia Falls School District 6" = c("Columbia Falls Elem", "Columbia Falls H S"),
  "Polson School District" = c("Polson Elem", "Polson H S"),
  "Lewistown Public Schools" = c("Lewistown Elem", "Fergus H S"),
  "Laurel Public Schools" = c("Laurel Elem", "Laurel H S"),
  "Kalispell Public Schools" = c("Kalispell Elem", "Flathead H S"),
  "Hardin Public Schools" = c("Hardin Elem", "Hardin H S"),
  "Glendive Public Schools" = c("Glendive Elem", "Dawson H S"),
  "Colstrip Public Schools" = c("Colstrip Elem", "Colstrip H S"),
  "Sidney Public Schools" = c("Sidney Elem", "Sidney H S"),
  "Stevensville Public Schools" = c("Stevensville Elem", "Stevensville H S"),
  "Big Sandy Public Schools" = c("Big Sandy K-12"),
  "Lame Deer Public Schools" = c("Lame Deer Elem", "Lame Deer H S"),
  "Poplar Public Schools" = c("Poplar Elem", "Poplar H S"),
  "Fairview Public Schools" = c("Fairview Elem", "Fairview H S"),
  "Rocky Boy Public Schools" = c("Rocky Boy Elem", "Rocky Boy H S"),
  "Ronan Public Schools" = c("Ronan Elem", "Ronan H S"),
  "Livingston Public Schools" = c("Livingston Elem", "Park H S"),
  "Lodge Grass Public Schools" = c("Lodge Grass Elem", "Lodge Grass H S"),
  "Wolf Point Public Schools" = c("Wolf Point Elem", "Wolf Point H S"),
  "Plentywood Public Schools" = c("Plentywood K-12 Schools"),
  # Elementary-only district (its high schoolers attend Whitefish H S, a separate board).
  "Olney-Bissell School District" = c("Olney-Bissell Elem")
)
