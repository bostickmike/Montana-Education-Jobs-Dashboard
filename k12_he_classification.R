# Shared classification/canonicalization logic for the K-12 and Higher Ed
# job-posting pipelines.
#
# Sourced from the pipeline entry point (both K-12 munge chunks and the
# Higher Ed munge chunk) so the two K-12 chunks can't drift apart, and
# reused verbatim by any one-off script that rebuilds the summary CSVs from
# the archived data without re-scraping. Keeping this in one file means
# "what the pipeline will produce next real run" and "what a
# rebuild-from-archive script produces now" can never silently diverge.
#
# Ported from the Wyoming Education Jobs Dashboard's k12_he_classification.R.
# The position/subject/job-type classification below is state-agnostic (job
# titles read the same in Montana as in Wyoming) and kept as-is.
# canonicalize_k12_district() and canonicalize_he_institution() are reset to
# empty pass-throughs below -- Wyoming's entries there fixed misspellings
# found in Wyoming's own scraped data and don't apply here. Real Montana
# entries get added to these as actual scraped-data typos turn up, the same
# way Wyoming's list grew one confirmed case at a time rather than being
# guessed in advance.

suppressMessages(library(dplyr))

# Normalize scraped text without corrupting text that is already valid UTF-8.
# Some legacy listings really do contain raw Windows-1252 bytes, but treating
# every string as Windows-1252 turns valid characters such as “é” into
# mojibake. Only strings that fail a UTF-8 round trip are repaired as CP1252.
normalize_posting_text <- function(x) {
  x <- as.character(x)
  missing <- is.na(x)
  valid_utf8 <- iconv(x, from = "UTF-8", to = "UTF-8", sub = NA_character_)
  needs_cp1252_repair <- !missing & is.na(valid_utf8)

  out <- x
  out[needs_cp1252_repair] <- iconv(
    x[needs_cp1252_repair],
    from = "WINDOWS-1252",
    to = "UTF-8",
    sub = "byte"
  )
  out <- enc2utf8(out)
  # Unescape common HTML entities that appear in scraped job titles / board text
  out <- gsub("&amp;", "&", out, fixed = TRUE)
  out <- gsub("&quot;", "\"", out, fixed = TRUE)
  out <- gsub("&#39;|&apos;", "'", out, perl = TRUE)
  out <- gsub("&lt;", "<", out, fixed = TRUE)
  out <- gsub("&gt;", ">", out, fixed = TRUE)
  out <- gsub("&nbsp;|\u00a0", " ", out, perl = TRUE)
  out <- gsub("[\r\n]+", " ", out)
  out <- trimws(out)
  out[missing] <- NA_character_
  out
}

# Kept as the classification-facing name while callers move to the general
# text normalizer above.
fix_title_encoding <- normalize_posting_text

normalize_posting_identity_component <- function(x) {
  out <- tolower(normalize_posting_text(x))
  gsub("\\s+", " ", out)
}

is_opi_statewide_posting <- function(url) {
  grepl(
    "apps\\.opi\\.mt\\.gov/mtjobsforteachers",
    normalize_posting_text(url),
    ignore.case = TRUE
  )
}

# A URL is a posting identity only when its path/query carries a known
# per-posting identifier. Board/listing URLs are deliberately not used: a
# board can host many simultaneous postings.
is_stable_posting_url <- function(url) {
  grepl(
    "(/jobs?/[^/?#]+|/job-list/[^/?#]+|ViewJob\\.aspx\\?JobID=|[?&](jobId|jobID|id)=|\\.pdf(?:[?#]|$))",
    normalize_posting_text(url),
    perl = TRUE
  )
}

# Builds the one K-12 identity contract used by current counts, historical
# aggregates, trends, and week-over-week matching. Direct structured listings
# use their stable per-posting URL. Sources without one (including OPI's
# WebForms feed) get an explicit, count-preserving fallback. Equal fallback
# records receive an occurrence suffix so they are not silently collapsed;
# that suffix is deterministic within a source snapshot, not a claim that OPI
# supplies a stable posting ID.
add_k12_posting_identity <- function(df) {
  required <- c("title", "location", "date_posted", "url", "District")
  missing <- setdiff(required, names(df))
  if (length(missing) > 0) {
    stop(
      "add_k12_posting_identity(): missing column(s): ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  # A row-level fallback, not a column-level one: some archived weeks
  # predate Posting_Source existing at all (see history_accumulator bug
  # writeup), and bind_rows()-ing those alongside newer weeks that do have
  # the column fills the older rows' value with NA rather than dropping
  # the column -- so "column present" is not the same as "every row has a
  # real value". Checking na/blank per row (instead of gating the whole
  # URL-based guess on whether the column exists anywhere in df) means an
  # old, column-less row and a new row with a genuinely blank
  # Posting_Source get identical, correct treatment: guess OPI from its
  # known URL, otherwise default to "Direct district board".
  url_based_source <- ifelse(is_opi_statewide_posting(df$url),
                              "OPI Jobs for Teachers (statewide)",
                              "Direct district board")
  if ("Posting_Source" %in% names(df)) {
    source <- normalize_posting_text(df$Posting_Source)
    missing_source <- is.na(source) | !nzchar(source)
    source[missing_source] <- url_based_source[missing_source]
  } else {
    source <- url_based_source
  }

  title <- normalize_posting_identity_component(df$title)
  location <- normalize_posting_identity_component(df$location)
  posted <- normalize_posting_identity_component(df$date_posted)
  district <- normalize_posting_identity_component(df$District)
  url <- normalize_posting_text(df$url)
  is_opi <- is_opi_statewide_posting(url) |
    source == "OPI Jobs for Teachers (statewide)"
  stable_url <- !is_opi & !is.na(url) & nzchar(url) & is_stable_posting_url(url)

  fallback_base <- paste(
    ifelse(is_opi, "opi-fallback", "source-fallback"),
    normalize_posting_identity_component(source),
    district,
    title,
    location,
    posted,
    sep = "\u001f"
  )
  fallback_occurrence_group <- fallback_base
  if ("Archive_Date" %in% names(df)) {
    fallback_occurrence_group <- paste(
      fallback_base,
      normalize_posting_identity_component(df$Archive_Date),
      sep = "\u001f"
    )
  }
  fallback_occurrence <- ave(
    seq_along(fallback_base),
    fallback_occurrence_group,
    FUN = seq_along
  )

  posting_id <- paste0("fallback:", fallback_base, "#", fallback_occurrence)
  posting_id[stable_url] <- paste0("url:", tolower(url[stable_url]))

  df$Posting_Source <- source
  df$Posting_Identity_Method <- ifelse(
    stable_url,
    "Stable per-posting URL",
    ifelse(
      is_opi,
      "OPI fallback: title + raw location + posted date (not a stable OPI ID)",
      "Source fallback: title + location + posted date (no stable posting URL)"
    )
  )
  df$Posting_ID <- posting_id
  df
}

summarize_k12_posting_counts <- function(k12jobs) {
  k12jobs %>%
    group_by(Broad_Category, Archive_Date, District) %>%
    summarize(sum = n_distinct(Posting_ID), .groups = "drop")
}

find_k12_new_postings <- function(k12_history) {
  dates <- sort(unique(as.Date(k12_history$Archive_Date)))
  if (length(dates) < 2) return(k12_history[0, , drop = FALSE])

  latest <- dates[length(dates)]
  previous <- dates[length(dates) - 1]
  k12_history %>%
    filter(as.Date(Archive_Date) == latest) %>%
    anti_join(
      k12_history %>% filter(as.Date(Archive_Date) == previous) %>% select(Posting_ID),
      by = "Posting_ID"
    )
}

# ---------------------------------------------------------------------------
# K-12
# ---------------------------------------------------------------------------

# Coarse position bucket from the raw job title.
classify_k12_position <- function(title) {
  title <- fix_title_encoding(title)
  dplyr::case_when(
    # Paraprofessional-related positions
    grepl("Paraprofessional|Para|Paraeducator|Teacher Assistant|Teaching Assistant|Instructional Assistant|Library Assistant|Media Assistant|Media Center Assistant", title, ignore.case = TRUE) ~ "Paraprofessional",

    # Substitute
    grepl("Sub|Substitute", title, ignore.case = TRUE) ~ "Substitute",

    # Teaching roles whose titles also carry a word claimed by an earlier
    # non-teaching rule below: ensemble "Band/Choir Director" (Administration)
    # and "Drivers Ed" (Transportation).
    grepl("\\b(Band|Choir|Choral|Orchestra|Music)\\s+Director\\b|\\bDriver'?s?\\s*Ed(ucation)?\\b|\\bTraffic Ed",
          title, ignore.case = TRUE) ~ "Teacher",

    # Support Services-related positions
    # \bIntern\b, not bare "Intern" -- matched inside "Internal Applicants Only"
    # otherwise, pulling teacher and bus-driver postings into this bucket.
    grepl("Counselor|Psychologist|Therapist|Pathologist|Occupational|Alternative Behavior Program|Audiologist|Lifeguard|Interpreter|Translator|Monitor|Safety Patrol|Social Worker|Technology Intern|Tutor|Instructional Facilitator|Resource Officer|Behavior|Occupational|Aide|Aid|Support|\\bIntern(ship)?s?\\b",
          title, ignore.case = TRUE) ~ "Support Services",

    # Staff-related positions (checked before Teacher so clerical titles like "General Secretary - Library" land here)
    grepl("Secretary|Clerk|Office Manager|Clerical|Registrar", title, ignore.case = TRUE) ~ "Staff",

    # Custodial/Maintenance-related positions
    grepl("Custodian|Custodial|Maintenance|Cleaner|Snow Removal|Facility|Electrician|HVAC",
          title, ignore.case = TRUE) ~ "Custodial/Maintenance",

    # Transportation-related positions
    # \bBus\b, not bare "Bus" -- matched inside "Business" otherwise.
    grepl("Bus Driver|Driver|Transportation|Route|\\bBus\\b|Mechanic|Bus Mechanic|Bus Monitor",
          title, ignore.case = TRUE) ~ "Transportation",

    # Technicians not already claimed by Custodial/Maintenance or Transportation
    # above; cafeteria technicians fall through to Food Services below.
    (grepl("Technician", title, ignore.case = TRUE) &
       !grepl("Food|Cook|Nutrition|Cafeteria|Dishwasher", title, ignore.case = TRUE)) ~ "Support Services",

    # Administration-related positions
    grepl("Principal|Director|Coordinator|Administrator|Supervisor|Administrative",
          title, ignore.case = TRUE) ~ "Administration",

    # Part-time / reduced-FTE teaching positions -- kept out of the full-FTE
    # "Teacher" bucket so they don't get counted equally with full teacher
    # postings in the subject-category trend charts.
    (grepl("Teacher|Instructor|Interventionist|English|Math|Library|Media|Language Arts|Science|Educator",
           title, ignore.case = TRUE) &
       grepl("Part[- ]?Time|Half[- ]?Time|\\b1/[2-9]th\\b|\\b0?\\.[1-9]\\s*FTE\\b",
             title, ignore.case = TRUE)) ~ "Part-Time Teacher",

    # Teacher-related positions
    grepl("Teacher|Instructor|Interventionist|English|Math|Library|Media|Language Arts|Science|Educator",
          title, ignore.case = TRUE) ~ "Teacher",

    # Coach-related positions
    # "Skiing" not bare "Ski" -- bare "Ski" matches inside "Life SKIlls".
    grepl("Coach|Athletic|Sports|Track|Football|Basketball|Golf|Soccer|Wrestling|Cheer|BB|Volleyball|Aquatics|Skiing",
          title, ignore.case = TRUE) ~ "Athletics",

    # Food Services-related positions
    grepl("Food|Cook|Nutrition|Cafeteria|Dishwasher", title, ignore.case = TRUE) ~ "Food Services",

    # Student Teaching-related positions
    grepl("Daycare|After School|Head Start", title, ignore.case = TRUE) ~ "Child Care",

    # Other positions
    TRUE ~ "Other"
  )
}

# Fine-grained subject category, computed only for position == "Teacher" rows.
k12_category_keywords <- list(
  "Technical Education" = "\\b(Welding|Weld|WeldingTeacher|CTE|Automotive|Auto(?!nomy)|Wood|Woods|Woodworking|Industrial Arts|Industrial Tech|Shop|Tech Ed|Technical Education|Trade and Technical|Drivers?\\s*Ed(ucation)?|Traffic Ed|Career and Technic(i)?al)\\b",
  "Agriculture Education" = "(\\b(Agriculture|Ag Teacher|Ag Program|Agricultural teacher|FFA|Vo[-/]?Ag)\\b|\\(AG\\))",
  "Computer Science Education" = "\\b(Computer Science|Information Technology|\\bIT\\b|Technology Education(?! Teacher Assistant)|Technology Teacher)\\b",
  # Pre[- ]?school covers "Preschool"/"Pre-school"/"Pre school" in one
  # pattern; Head Start is a real, common federal early-childhood program
  # name that doesn't otherwise contain any of the other keywords here.
  "Early Childhood Education" = "\\b(Early Childhood|Pre\\s*[- ]?\\s*K(?!indergarten)|Pre\\s*[- ]?\\s*school|Birth to age|Ages 3-5|Head Start|Toddler|Daycare|Early Learning|\\bSACC\\b)\\b",
  "Elementary Education" = "\\b(Elementary|Kindergarten|1st|2nd|3rd|4th|5th|First|Second|Third|Fourth|Fifth|Grade [1-7]|Grades?\\s*K-[1-7]|K-[1-7]\\s*Teacher|Classroom Teacher|Colony Teacher|Sixth Grade|6th Grade|Seventh Grade|7th Grade|Primary Grade|Primary Teacher)\\b",
  # "Literacy/Reading Interventionist" specifically (not bare "Interventionist"
  # or "Academic Interventionist" -- those don't name a subject and are
  # genuinely ambiguous, left as Uncategorized rather than guessed).
  "English Language Arts Education" = "(?i)\\b(English(?!\\s+as\\s+a\\s+Second\\s+Language|\\s+Learner|\\s+Language\\s+Learner)|ELA|Language Arts(?!\\s*Coordinator)|(Literacy|Reading) Interventionist|Title\\s*(One|1|I)\\b|Reading Recovery|Literacy Teacher|Reading Teacher|Literacy Specialist|Reading and Writing|Intervention Teacher|Teacher Reading)\\b",
  "Family and Consumer Science" = "\\b(Family and Consumer Sciences?|FCS|Home Economics)\\b",
  "Language Education" = "\\b(ESL|ELL|English as a Second Language|English Learner|Bilingual|Spanish|French|Dual Language|World Language|Foreign Language|Arapaho|Arapahoe|Shoshone|Salish|Kootenai|Cree|Crow|Blackfeet|Cheyenne|Assiniboine|Lakota|Dakota|Native Language|Indigenous Language|Culture Teacher|\\bEL Teacher\\b|\\bELL Teacher\\b|\\bESL Teacher\\b)\\b",
  "Mathematics Education" = "\\b(Mathematics|\\bMath\\b)\\b",
  "Music Education" = "\\b(Music|Orchestra|Band|Choir|Chorus|Vocal)\\b",
  "Health Science" = "(?i)\\b(Nurse Educator|Health Science(s)? Teacher|Health Science(s)?|Certified Nursing Assistant|Nursing Assistant|CNA)\\b",
  "Science Education" = "\\b(Science|Biology|Chemistry|Physics|Earth Science)\\b",
  "Social Studies Education" = "\\b(Social Studies|History|Geography|Civics|Political Science|\\bSS Teacher\\b)\\b",
  # Special Education tends to be the single largest category by a wide
  # margin, so it's split into two here rather than left as one monolithic
  # bucket: program types that are specifically resource-room/life-skills/
  # functional programs, vs. general/core special education. Checked in
  # that order (more specific first) since a title can plausibly contain
  # both kinds of words.
  "Special Education - Resource/Life Skills" = "\\b(Resource (Teacher|Room)|Life Skills|Affective Needs|Daily Living Skills|Special Needs|\\bPALS\\b|\\bSE - TEACHER LS\\b|\\bACP\\b|Alternative Communication(s)? Program)\\b",
  "Special Education - General" = "\\b(Special[- ]Educat(i)?on|Special Ed\\.?\\b|SPED|Exceptional Children|Deaf|Visually Impaired|Autism|\\bASD\\b|\\bSE - TEACHER\\b|\\bSE TEACHER\\b|\\bSp\\.?\\s*Ed\\b|Disabilities Educator)\\b",
  "Physical Education" = "(?i)\\b(Physical Education|P\\.?E\\.?|PE\\s*/\\s*Health|Health\\s*/\\s*PE|Health and Physical Education|Phys\\.?\\s*Ed\\.?|Water Safety|Pickleball|Yoga|Aquatics|Lifeguard Instructor)\\b",
  "Business and Economics" = "\\b(Business|Economics|Econ|Financial Literacy)\\b",
  # "Guest Teacher" is a common euphemism for substitute teacher used by
  # some districts/staffing agencies (e.g. Kelly Education), not a distinct
  # role.
  "Substitute Teaching" = "(?i)\\b(Substitute Teacher|Sub Teacher|Guest Teacher(s)?)\\b",
  "Virtual Education" = "\\b(Virtual|Remote|Online)\\b",
  "Art Teacher" = "\\b(Art Teacher|\\bArt\\b|Visual Art|Pottery|Sculpture|Drawing|Ceramics|Theater|Theatre|Drama)\\b",
  "STEM Teacher" = "\\b(STEM|STEAM|Robotics)\\b",
  # JROTC/military-science instructors fold into CTE, matching how many
  # state frameworks classify JROTC.
  "CTE Teacher" = "\\b(Career and Technical Education|CTE Teacher|JROTC|ROTC|Military Instructor|Aviation Teacher)\\b",
  "Library Media" = "\\b(Library|Librarian|Media Specialist|Library Media)\\b",
  "Gifted and Talented" = "\\b(Gifted|Talented|GATE|Advanced Learning)\\b"
)

classify_k12_subject <- function(title) {
  title <- fix_title_encoding(title)
  kw <- k12_category_keywords
  dplyr::case_when(
    stringr::str_detect(title, stringr::regex(kw[["Special Education - Resource/Life Skills"]], ignore_case = TRUE)) ~ "Special Education - Resource/Life Skills",
    stringr::str_detect(title, stringr::regex(kw[["Special Education - General"]], ignore_case = TRUE)) ~ "Special Education - General",
    stringr::str_detect(title, stringr::regex(kw[["Technical Education"]], ignore_case = TRUE)) ~ "Technical Education",
    stringr::str_detect(title, stringr::regex(kw[["Agriculture Education"]], ignore_case = TRUE)) ~ "Agriculture Education",
    stringr::str_detect(title, stringr::regex(kw[["Computer Science Education"]], ignore_case = TRUE)) ~ "Computer Science Education",
    stringr::str_detect(title, stringr::regex(kw[["Early Childhood Education"]], ignore_case = TRUE)) ~ "Early Childhood Education",
    stringr::str_detect(title, stringr::regex(kw[["Elementary Education"]], ignore_case = TRUE)) ~ "Elementary Education",
    stringr::str_detect(title, stringr::regex(kw[["English Language Arts Education"]], ignore_case = TRUE)) ~ "English Language Arts Education",
    stringr::str_detect(title, stringr::regex(kw[["Family and Consumer Science"]], ignore_case = TRUE)) ~ "Family and Consumer Science",
    stringr::str_detect(title, stringr::regex(kw[["Language Education"]], ignore_case = TRUE)) ~ "Language Education",
    stringr::str_detect(title, stringr::regex(kw[["Mathematics Education"]], ignore_case = TRUE)) ~ "Mathematics Education",
    stringr::str_detect(title, stringr::regex(kw[["Music Education"]], ignore_case = TRUE)) ~ "Music Education",
    stringr::str_detect(title, stringr::regex(kw[["Physical Education"]], ignore_case = TRUE)) ~ "Physical Education",
    stringr::str_detect(title, stringr::regex(kw[["Health Science"]], ignore_case = TRUE)) ~ "Health Science",
    stringr::str_detect(title, stringr::regex(kw[["Science Education"]], ignore_case = TRUE)) ~ "Science Education",
    stringr::str_detect(title, stringr::regex(kw[["Social Studies Education"]], ignore_case = TRUE)) ~ "Social Studies Education",
    stringr::str_detect(title, stringr::regex(kw[["Business and Economics"]], ignore_case = TRUE)) ~ "Business and Economics",
    stringr::str_detect(title, stringr::regex(kw[["Substitute Teaching"]], ignore_case = TRUE)) ~ "Substitute Teaching",
    stringr::str_detect(title, stringr::regex(kw[["Virtual Education"]], ignore_case = TRUE)) ~ "Virtual Education",
    stringr::str_detect(title, stringr::regex(kw[["Art Teacher"]], ignore_case = TRUE)) ~ "Art Teacher",
    stringr::str_detect(title, stringr::regex(kw[["STEM Teacher"]], ignore_case = TRUE)) ~ "STEM Teacher",
    stringr::str_detect(title, stringr::regex(kw[["CTE Teacher"]], ignore_case = TRUE)) ~ "CTE Teacher",
    stringr::str_detect(title, stringr::regex(kw[["Library Media"]], ignore_case = TRUE)) ~ "Library Media",
    stringr::str_detect(title, stringr::regex(kw[["Gifted and Talented"]], ignore_case = TRUE)) ~ "Gifted and Talented",
    TRUE ~ "Uncategorized"
  )
}

# Rebalances two oversized, artificially-merged buckets from k12_category_keywords
# above into coherent groups for the app's category color palettes/pickers.
# Special Education's own split happens earlier, at the subject-category
# level (see k12_category_keywords above), and passes through unchanged here.
classify_k12_broad_category <- function(category) {
  dplyr::case_when(
    category == "Agriculture Education" ~ "CTE - Trades, Ag & Technical",
    category == "Art Teacher" ~ "Art",
    category == "Business and Economics" ~ "CTE - Business & Family Sciences",
    category == "Computer Science Education" ~ "CTE - Business & Family Sciences",
    category == "Early Childhood Education" ~ "Early Childhood",
    category == "Elementary Education" ~ "Elementary",
    category == "English Language Arts Education" ~ "English Language Arts Secondary",
    category == "Family and Consumer Science" ~ "CTE - Business & Family Sciences",
    category == "Health Science" ~ "CTE - Business & Family Sciences",
    category == "Language Education" ~ "Language",
    category == "Mathematics Education" ~ "Math",
    category == "Music Education" ~ "Music",
    category == "Physical Education" ~ "Physical Education",
    category == "STEM Teacher" ~ "Science",
    category == "Science Education" ~ "Science",
    category == "Social Studies Education" ~ "Secondary Social Studies",
    category == "Special Education - General" ~ "Special Education - General",
    category == "Special Education - Resource/Life Skills" ~ "Special Education - Resource/Life Skills",
    category == "Technical Education" ~ "CTE - Trades, Ag & Technical",
    category == "CTE Teacher" ~ "CTE - Trades, Ag & Technical",
    category == "Uncategorized" ~ "Other",
    category == "Virtual Education" ~ "Other",
    category == "Library Media" ~ "Library Media",
    category == "Gifted and Talented" ~ "Gifted and Talented",
    TRUE ~ "Other"
  )
}

# Fixes known misspellings of district names at the source so the same
# district doesn't get silently split into two "different" districts in the
# dashboard's dropdowns/trend lines. Empty for now -- no Montana district
# name typos have been confirmed in scraped data yet. Add real cases here as
# they're found, the same way Wyoming's list grew one confirmed case at a
# time rather than being guessed in advance. A plain passthrough rather than
# case_when(TRUE ~ district) -- that form (scalar LHS, vector RHS) is
# deprecated as of dplyr 1.2.0 and would warn on every pipeline run.
canonicalize_k12_district <- function(district) {
  district
}

# ---------------------------------------------------------------------------
# Higher Ed
# ---------------------------------------------------------------------------

# Coarse job-type bucket from the raw posting title. Adjunct/pooled titles
# get their own bucket, separate from "Instructor/Teacher/Faculty", so
# standing adjunct-pool postings don't get counted the same as full-time
# faculty hiring in the faculty trend charts.
classify_he_job_type <- function(title) {
  dplyr::case_when(
    # Adjunct / part-time pool positions. A bare "Part-Time" is not enough on
    # its own -- plenty of real non-faculty postings ("Custodian 1-Part-Time",
    # "Major Gift Officer - Part-time", "Part-Time Clinical Resource
    # Registered Nurse") also contain that phrase, so it only counts here
    # alongside an actual faculty-role word.
    grepl("Adjunct", title, ignore.case = TRUE) |
      (grepl("Part[- ]?Time", title, ignore.case = TRUE) &
         grepl("Faculty|Instructor|Professor|Lecturer|Teacher", title, ignore.case = TRUE)) ~
      "Adjunct/Part-Time Faculty",

    # Administration & Faculty Affairs (checked before teaching faculty so administrative Provost roles don't land in faculty)
    grepl("Faculty Affairs|Faculty Development|Provost Office|Office of the Provost", title, ignore.case = TRUE) ~ "Administration",

    # Instructor/Teacher/Faculty
    grepl("Instructor|Instructional|Teacher|Faculty|Professor|Lecturer|Post Doc|Subject Matter Expert|Librarian|Educator", title, ignore.case = TRUE) ~ "Instructor/Teacher/Faculty",

    # Student Positions
    grepl("Student Worker|Student Position|Work Study|Students Only|Student Library Aid|Student Employment", title, ignore.case = TRUE) ~ "Student Positions",

    # Healthcare
    grepl("Nurse|Wellbeing|Health|Medicine|Medical Support Assistant", title, ignore.case = TRUE) ~ "Healthcare",

    # Temporary Position
    grepl("Pooled Position|Temporary|Monthly Pooled", title, ignore.case = TRUE) ~ "Temporary Position",

    # Staff (consolidated all office assistant/associate roles)
    grepl("Hourly|Administrative Assistant|Administrative Associate|Secretary|Library Assistant|Office Assistant|Office Associate",
          title, ignore.case = TRUE) ~ "Staff",

    # Advising
    grepl("Advisor|Advising|Enrollment Counselor|Financial Aid|Peer Tutor|Tribal Education Assistant", title, ignore.case = TRUE) ~ "Advising and Student Services",

    # Culinary -- checked before Maintenance & Service so "Cook"/"Baker"
    # land here instead of being swallowed by Maintenance & Service's own
    # copy of the same words.
    grepl("Chef|Cook|Baker|Dining|Culinary", title, ignore.case = TRUE) ~ "Culinary",

    # Professional
    grepl("Admissions|Coordinator|Registrar|Executive Assistant|Professional|Statistician|Proctor|Exec Assistant|Grant Writer|Graphic Designer|Negotiator|Botanist|College Relations|Controller|Database|Officer|Auditor|Web Site|Special Assistant|Retention Mentor|Data Analyst|Employee Relations Specialist|Finance Technician|Grant Support Specialist|Marketing & Comm Spec.|Program Specialist",
          title, ignore.case = TRUE) ~ "Professional",

    # Administration
    grepl("\\bDean\\b|Vice President|Provost|Chief|Business Manager|Enrollment Specialist|Finance Technician|HR Records Specialist", title, ignore.case = TRUE) ~ "Administration",

    # Coaching or Athletics
    grepl("coach|Athletic|Athletics", title, ignore.case = TRUE) ~ "Coaching or Athletics",

    # Accounting/Finance
    grepl("Accountant|Receivable|Accounts", title, ignore.case = TRUE) ~ "Accounting/Finance",

    # Research & Science (only actual research/scientific roles)
    grepl("Research Associate|Laboratory Technician|Research Scientist", title, ignore.case = TRUE) ~ "Research & Science",

    # Technical -- bare "Specialist" excluded (it shadows later, more
    # specific buckets like Support Services' "Library Information
    # Specialist"; only qualified "<Thing> Specialist" phrases stay here).
    grepl("Control Specialist|Engineer|IT Support Technician|Information Security Analyst|Programmer Analyst|Network Specialist|Data Operation Engineer|Design Engineer|GIS Specialist", title, ignore.case = TRUE) ~ "Technical",

    # Maintenance & Service ("Cook"/"Baker" excluded -- see Culinary above)
    grepl("Maintenance|Technician|Facilities|Grounds|HVAC|Plumber|Carpenter|Logistics Handler", title, ignore.case = TRUE) ~ "Maintenance & Service",

    # Support Services
    grepl("Safety|Security|Custodian|Laborer|Driver|Cleaner|Facilities|Grounds|Library Information Specialist|Museum Exhibit Specialist|Specialist, Student Services|Lifeguard|Resident Assistant",
          title, ignore.case = TRUE) ~ "Support Services",

    # Management ("Coordinator" excluded -- Professional's own copy of that
    # keyword is checked earlier and always wins, making a copy here dead
    # code).
    grepl("Director|\\bDirector\\b|Manager|Supervisor|Assoc Director|Assoc Dir|Assist Dir|Asst Dir",
          title, ignore.case = TRUE) ~ "Management",

    TRUE ~ "Other"
  )
}

# Subject category, computed only for Job_Type == "Instructor/Teacher/Faculty" rows.
classify_he_faculty_category <- function(title) {
  dplyr::case_when(
    # 1. Legal & Criminal Justice
    grepl("criminal justice|criminology|corrections|law enforcement|police|forensic|homeland security|justice studies", title, ignore.case = TRUE) ~ "Criminal Justice",
    grepl("law|legal|college of law|paralegal|juris doctor|\\bjd\\b|crimin(al)? law", title, ignore.case = TRUE) ~ "Legal",

    # 2. Extension / Outreach
    grepl("extension educator|extension specialist|\\bextension\\b|4-h", title, ignore.case = TRUE) ~ "Extension/Outreach",

    # 3. Culinary & Hospitality (before Business so Hospitality in College of Business lands here)
    grepl("culinary|hospitality|tourism|baking|food service|restaurant|hotel|brewing", title, ignore.case = TRUE) ~ "Culinary/Hospitality",

    # 4. Human Services / Social Work / Counseling (before Education / Health)
    grepl("human services?|social work|\\bmsw\\b|counseling|counselor|mental health|substance abuse|addiction|chemical dependency|\\bhdch\\b|child development|youth", title, ignore.case = TRUE) ~ "Human Services",

    # 5. CTE - Health Sciences (before general Science so "Health Sciences" lands here)
    grepl("health technology|nursing|\\brn\\b|\\blpn\\b|dental|ems|paramedic|emergency medical|emergency care|\\becp\\b|medical|medicine|nutritional|nutrition|dietetics|pharmacy|pharmacist|global health|public health|allied health|health sciences?|physician assistant|physical therapy|occupational therapy|speech-language|pathology|audiol|respiratory therapy|surgical tech|phlebotom|radiolog|x-ray|sonograph|ultrasound|biomed|clinical|medical assistant", title, ignore.case = TRUE) ~ "CTE - Health Sciences",

    # 6. Social Science (before general Science so "Political Science", "Social Sciences", "Native American Studies" land here)
    grepl("social sciences?|political science|politics|government|public policy|public administration|tribal governance|native american studies|indigenous studies|ethnic studies|african american studies|chicano|latinx|gender|sexuality|women|international relations|global studies|sociology|sociological|anthropology|psychology|psychological|behavior|geography|urban planning", title, ignore.case = TRUE) ~ "Social Science",

    # 7. Languages (including Indigenous and non-European)
    grepl("spanish|foreign language|world language|french|german|japanese|arabic|chinese|russian|italian|latin|greek|salish|kootenai|cree|crow|blackfeet|cheyenne|assiniboine|lakota|dakota|shoshone|arapaho|linguistics|\\basl\\b|sign language|\\besl\\b|\\bell\\b|tesol|language instructor", title, ignore.case = TRUE) ~ "Language",

    # 8. History
    grepl("history|historical|heritage|museum studies", title, ignore.case = TRUE) ~ "History",

    # 9. Physical Education
    grepl("physical education|\\bpe\\b|outdoor activity|outdoor recreation|recreation|athletic train|kinesiology|strength|sports management|exercise science|fitness|wellness|activity class|coach", title, ignore.case = TRUE) ~ "Physical Education",

    # 10. The Arts
    grepl("\\bart\\b|visual art|fine arts?|studio art|graphic design|design|theater|theatre|drama|acting|music|musical|vocal|choir|instrumental|band|orchestra|ceramics|sculpture|painting|drawing|photography|photo|film|cinema|animation|media arts?|digital media|dance|jewelry|metalsmithing", title, ignore.case = TRUE) ~ "The Arts",

    # 11. Education (including instructional technology)
    grepl("instructional technology|instructional design|early childhood|preschool|daycare|child care|asum child care|elementary education|secondary education|special education|teacher prep|reading specialist|stem education|learning center|college success|pedagogy|curriculum|leadership fellows|educational leadership|education|educational", title, ignore.case = TRUE) ~ "Education",

    # 12. Library
    grepl("library|librarian|library media|archivist|archives", title, ignore.case = TRUE) ~ "Library",

    # 13. Math
    grepl("math|mathematics|statistics|biostatistics|actuarial|data analytics", title, ignore.case = TRUE) ~ "Math",

    # 14. Humanities
    grepl("philosophy|english|communication|literature|mass communication|humanities|liberal studies|liberal arts|texts and critics|public speaking|rhetoric|writing|creative writing|journalism|religious studies|religion|ethics|folklore|classics|american studies|cultural studies|cls seminar", title, ignore.case = TRUE) ~ "Humanities",

    # 15. CTE - Business & Computing (includes Agricultural Economics BEFORE general Agricultural!)
    grepl("agricultural economics|agricultural business|computer science|computer|information technology|computing|cybersecurity|data science|software|informatics|information systems|\\bcis\\b|network|web development|artificial intelligence|\\bai\\b|machine learning|business|accounting|finance|financial planning|family financial|economics|\\becon\\b|management|marketing|commerce|entrepreneurship|\\bmba\\b|business administration|real estate|banking|\\biv&v\\b|verification & validation", title, ignore.case = TRUE) ~ "CTE - Business & Computing",

    # 16. CTE - Trades & Engineering
    grepl("agricultural communications|\\bagricultural\\b|\\bag mechanics?\\b|ag instructor|college of ag|heavy equipment|\\bheo\\b|mechanic|welding|construction|hvac|electrical|powerline|lineman|substation|diesel|automotive|auto body|\\bcdl\\b|commercial driver|truck driving|transportation|drafting|architecture|architect|aviation|pilot|flight|\\buas\\b|drone|unmanned aerial|surveying|geomatics|mining|machine tool|manufacturing|industrial|printmaking|supply chain|logistics|carpentry|plumbing|engineering|engineer|energy|equine", title, ignore.case = TRUE) ~ "CTE - Trades & Engineering",

    # 17. Science (Zoology now here; Political Science & Health Sciences safely filtered above)
    grepl("chemistry|biology|physics|astronomy|\\blab\\b|laboratory|geology|geoscience|earth science|environmental science|environmental studies|ecology|ecological|agronom|agriculture|animal science|veterinary|vet tech|plant science|soils?|hydrology|water resources|forestry|wildlife|natural resources|conservation|fisheries|range(land)? management|microbiology|biochem|neuroscience|genetics|botany|zoology|meteorology|atmospheric|\\bmsse\\b|science", title, ignore.case = TRUE) ~ "Science",

    TRUE ~ "Uncategorized"
  )
}

# Fixes known misspellings of institution names at the source, the HE analog
# of canonicalize_k12_district() above. Empty for now -- no Montana
# institution name typos have been confirmed in scraped data yet. Plain
# passthrough for the same case_when(TRUE ~ ...) deprecation reason as
# canonicalize_k12_district() above.
canonicalize_he_institution <- function(institution) {
  institution
}
