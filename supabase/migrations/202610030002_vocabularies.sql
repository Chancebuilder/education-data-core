-- Controlled vocabularies. Application code should treat these codes as stable.

create table vocab.verification_status (
  code text primary key,
  label text not null,
  description text not null,
  may_present_as_established_fact boolean not null
);

insert into vocab.verification_status (code, label, description, may_present_as_established_fact) values
  ('unknown', 'Unknown', 'The verification state was not recorded.', false),
  ('unreviewed', 'Unreviewed', 'Loaded and not yet reviewed.', false),
  ('machine_extracted', 'Machine extracted', 'Extracted by a parser and not yet confirmed by a person.', false),
  ('needs_review', 'Needs review', 'A person should confirm the fact before clients rely on it.', false),
  ('source_confirmed', 'Source confirmed', 'The cited source states this fact. Degree Agency has not performed a second manual audit beyond the research extract.', true),
  ('verified', 'Verified', 'A reviewer confirmed the fact against the authoritative source after the initial extract.', true),
  ('institution_confirmed', 'Institution confirmed', 'The destination institution confirmed the fact.', true),
  ('conflicting_sources', 'Conflicting sources', 'Sources disagree. Do not collapse them into one winner.', false),
  ('stale', 'Stale', 'The fact is older than the review window and should be rechecked.', false),
  ('expired', 'Expired', 'The fact''s own validity period has ended.', false),
  ('superseded', 'Superseded', 'A later assertion replaced this one in Degree Agency''s records.', false),
  ('inferred', 'Inferred', 'Derived rather than stated by the source. Must never be presented as verified.', false);

create table vocab.confidence_level (
  code text primary key,
  label text not null,
  description text not null
);

insert into vocab.confidence_level (code, label, description) values
  ('high', 'High', 'The source statement is specific and the extract captured it directly.'),
  ('medium', 'Medium', 'The source supports the fact, with a narrower or partly summarized statement.'),
  ('low', 'Low', 'The support is thin. Prefer a research gap over a strong claim.'),
  ('unknown', 'Unknown', 'Confidence was not assessed.');

create table vocab.evidence_role (
  code text primary key,
  description text not null
);

insert into vocab.evidence_role (code, description) values
  ('supports', 'The evidence supports the fact.'),
  ('contradicts', 'The evidence conflicts with the fact.'),
  ('supersedes', 'The evidence replaces an earlier fact.'),
  ('discovery_only', 'The evidence only helped find the record and does not by itself establish the fact.');

create table vocab.source_type (
  code text primary key,
  description text not null
);

insert into vocab.source_type (code, description) values
  ('academic_catalog', 'Institutional academic catalog.'),
  ('registrar_policy', 'Registrar or academic-policy page.'),
  ('institution_transfer_database', 'Institution transfer-credit database or tool.'),
  ('articulation_agreement', 'Articulation agreement.'),
  ('institution_program_page', 'Official program page.'),
  ('institution_about_page', 'Official institutional identity or about page.'),
  ('ace_national_guide', 'ACE National Guide.'),
  ('nccrs_directory', 'National CCRS directory or organization record.'),
  ('usde_dapip', 'U.S. Department of Education DAPIP or accreditation database.'),
  ('accreditor_directory', 'Accreditor directory or public notice.'),
  ('provider_page', 'Provider catalog or marketing page. Provider claims are not institutional acceptance.'),
  ('archived_webpage', 'Archived copy of a webpage.'),
  ('official_correspondence', 'Letter, email, or other official correspondence.'),
  ('government_notice', 'Government notice other than DAPIP.'),
  ('news_release', 'Institutional or agency news release.'),
  ('third_party_discovery', 'Secondary discovery source, including the Degree Agency research extract when a primary URL was not retained.');

create table vocab.authority_scope (
  code text primary key,
  description text not null
);

insert into vocab.authority_scope (code, description) values
  ('identity_history', 'Names, dates of use, and institutional succession.'),
  ('institutional_policy', 'The institution''s own transfer or prior-learning policy.'),
  ('institutional_equivalency', 'The destination institution''s equivalency or transfer-database decision.'),
  ('institutional_accreditation', 'Accreditation of an institution or program.'),
  ('accreditor_recognition', 'Recognition of an accreditor by a government or recognition body.'),
  ('program_requirements', 'Requirements of a program version.'),
  ('recommendation_body', 'ACE, NCCRS, or another recommendation body, authoritative for its own recommendation only.'),
  ('government_record', 'Government record such as a closure or recognition action.'),
  ('provider_claim', 'A claim published by a provider. It does not bind a destination institution.'),
  ('discovery_only', 'Discovery aid, not the authority for the fact.');

create table vocab.extraction_method (
  code text primary key,
  description text not null
);

insert into vocab.extraction_method (code, description) values
  ('deep_research_report', 'Captured in the October 3, 2026 Degree Agency deep-research verification pass.'),
  ('manual', 'Entered by a reviewer.'),
  ('machine_extraction', 'Parser or crawler output.'),
  ('registrar_export', 'Registrar data export.'),
  ('api_import', 'Imported from a source API.'),
  ('unknown', 'Method not recorded.');

create table vocab.alias_type (
  code text primary key,
  description text not null
);

insert into vocab.alias_type (code, description) values
  ('official_name', 'Name that was or is the official institutional name.'),
  ('former_name', 'Earlier official name retained for matching and history.'),
  ('trade_name', 'Public or trade name.'),
  ('abbreviation', 'Abbreviation or acronym used in the research extract.'),
  ('other', 'Other alias.');

create table vocab.identifier_type (
  code text primary key,
  description text not null
);

insert into vocab.identifier_type (code, description) values
  ('IPEDS_UNITID', 'NCES IPEDS UNITID.'),
  ('OPEID', 'Office of Postsecondary Education identifier.'),
  ('DAPIP_ID', 'Department of Education DAPIP identifier.'),
  ('INSTITUTION_CODE', 'Institution-assigned code.'),
  ('OTHER', 'Another issuer''s identifier.');

create table vocab.institution_status (
  code text primary key,
  description text not null
);

insert into vocab.institution_status (code, description) values
  ('active', 'Operating, as of the assertion''s validity.'),
  ('closed', 'Closed.'),
  ('merged', 'Merged into another institution.'),
  ('unknown', 'Status was not established.');

create table vocab.institution_type (
  code text primary key,
  description text not null
);

insert into vocab.institution_type (code, description) values
  ('university', 'Uses the institutional class university in its official name or authorizing description.'),
  ('college', 'Uses the institutional class college.'),
  ('community_college', 'Community or junior college.'),
  ('technical_institute', 'Technical institute.'),
  ('system_office', 'University system office rather than a teaching campus.'),
  ('other', 'Another class.'),
  ('unknown', 'Class not established.');

create table vocab.institution_control (
  code text primary key,
  description text not null
);

insert into vocab.institution_control (code, description) values
  ('public', 'Public control.'),
  ('private_nonprofit', 'Private nonprofit.'),
  ('private_for_profit', 'Private for-profit.'),
  ('unknown', 'Control not established.');

create table vocab.accreditation_status (
  code text primary key,
  description text not null
);

insert into vocab.accreditation_status (code, description) values
  ('accredited', 'Accredited.'),
  ('preaccredited', 'Preaccredited or candidate, when the source uses that status.'),
  ('resigned', 'Accreditation resigned.'),
  ('withdrawn', 'Accreditation withdrawn.'),
  ('terminated', 'Accreditation or recognition terminated.'),
  ('expired', 'Accreditation expired.'),
  ('participating', 'Participates in a system or parent accreditation structure. This is not a claim of a standalone grant.'),
  ('unknown', 'Status not established.');

create table vocab.accreditation_scope (
  code text primary key,
  description text not null
);

insert into vocab.accreditation_scope (code, description) values
  ('institutional', 'Institutional accreditation.'),
  ('programmatic', 'Programmatic or specialized accreditation.'),
  ('university_system_participation', 'Participation in a university system''s accreditation structure.'),
  ('unknown', 'Scope not established.');

create table vocab.recognition_status (
  code text primary key,
  description text not null
);

insert into vocab.recognition_status (code, description) values
  ('recognized', 'Recognized by the named authority.'),
  ('terminated', 'Recognition terminated.'),
  ('withdrawn', 'Recognition withdrawn.'),
  ('reinstated', 'Recognition reinstated.'),
  ('unknown', 'Recognition status not established.');

create table vocab.degree_type (
  code text primary key,
  description text not null
);

insert into vocab.degree_type (code, description) values
  ('associate', 'Associate degree.'),
  ('bachelor', 'Bachelor''s degree.'),
  ('master', 'Master''s degree.'),
  ('doctoral', 'Doctoral degree.'),
  ('certificate', 'Certificate or other undergraduate credential below an associate degree.'),
  ('other', 'Another credential.'),
  ('unknown', 'Credential level not established.');

create table vocab.credit_unit (
  code text primary key,
  description text not null
);

insert into vocab.credit_unit (code, description) values
  ('semester', 'Semester credit.'),
  ('quarter', 'Quarter credit.'),
  ('clock_hour', 'Clock hour.'),
  ('unspecified', 'The source said credits or hours without naming the unit. Do not convert.'),
  ('unknown', 'Unit not discussed.');

create table vocab.academic_level (
  code text primary key,
  description text not null
);

insert into vocab.academic_level (code, description) values
  ('lower_division', 'Lower division.'),
  ('upper_division', 'Upper division.'),
  ('vocational', 'Vocational.'),
  ('graduate', 'Graduate.'),
  ('mixed', 'More than one level.'),
  ('unknown', 'Level not established.');

create table vocab.date_precision (
  code text primary key,
  description text not null
);

insert into vocab.date_precision (code, description) values
  ('day', 'The calendar day is established.'),
  ('month', 'The month is established. The stored day is not meaningful.'),
  ('year', 'The year is established. The stored month and day are not meaningful and are kept as January 1 by convention.'),
  ('unknown', 'No date was established. A null date should accompany this precision.');

create table vocab.policy_kind (
  code text primary key,
  description text not null
);

insert into vocab.policy_kind (code, description) values
  ('transfer_acceptance', 'Whether and how outside learning may be accepted.'),
  ('transfer_maximum', 'Caps on transferable credit, including the explicit absence of a cap.'),
  ('residency', 'Credits that must be completed at the destination institution.'),
  ('minimum_grade', 'Grade thresholds.'),
  ('course_age', 'How course age affects transfer or application.'),
  ('alternative_credit', 'Alternative credit, exams, ACE/NCCRS, or prior-learning rules.'),
  ('source_accreditation', 'Rules that depend on the source institution''s accreditor.'),
  ('transcript_routing', 'How evidence or transcripts must be submitted.'),
  ('prior_learning', 'Prior-learning assessment methods.'),
  ('other', 'Another policy kind.');

create table vocab.policy_fact_kind (
  code text primary key,
  description text not null
);

insert into vocab.policy_fact_kind (code, description) values
  ('transfer_maximum', 'A maximum, a typical maximum, or a differentiated maximum whose number may still be unknown.'),
  ('no_transfer_limit', 'The institution states that it does not set a numeric transfer cap. Residency rules may still apply.'),
  ('residency_minimum', 'A minimum that must be completed at the destination.'),
  ('minimum_grade', 'A grade rule. The threshold may be null when the source only says a distinct threshold exists.'),
  ('course_age', 'A course-age rule. The duration may be null when it was not captured.'),
  ('alternative_credit_limit', 'A cap on a category of alternative or noncollegiate credit.'),
  ('acceptance_condition', 'A condition under which a category of learning is considered. It does not by itself accept a named course.'),
  ('source_distinction', 'The institution treats source types or partners differently.'),
  ('transcript_routing', 'Submission-channel rule.'),
  ('program_restriction', 'Program-specific restriction or override whose details may be incomplete.'),
  ('application_note', 'How accepted credit may apply differently, without a full requirement mapping.');

create table vocab.comparison_operator (
  code text primary key,
  description text not null
);

insert into vocab.comparison_operator (code, description) values
  ('max', 'Maximum.'),
  ('min', 'Minimum.'),
  ('no_set_limit', 'The source states there is no set numeric limit.'),
  ('conditional', 'Conditional, with the statement carrying the condition.'),
  ('unspecified', 'The comparison exists in the source but the number or operator was not captured.');

create table vocab.acceptance_status (
  code text primary key,
  description text not null
);

insert into vocab.acceptance_status (code, description) values
  ('accepted', 'The source explicitly accepts the scoped learning.'),
  ('conditional', 'The source may accept the scoped learning when stated conditions are met.'),
  ('rejected', 'The source explicitly rejects the scoped learning.'),
  ('not_documented', 'Acceptance was not established.'),
  ('unknown', 'Acceptance state was not assessed.');

create table vocab.acceptance_strength (
  code text primary key,
  description text not null
);

insert into vocab.acceptance_strength (code, description) values
  ('none', 'The fact does not establish acceptance of a course or provider.'),
  ('category_illustrative', 'The source names a category with hedges such as certain, eligible, such as, or subject to program review. It does not establish acceptance of an unnamed course.'),
  ('category_explicit', 'The source explicitly accepts a defined category. V1 still does not treat that as a course equivalency.'),
  ('provider', 'The source explicitly accepts a named provider.'),
  ('course', 'The source explicitly accepts a named course or exam.');

create table vocab.source_category (
  code text primary key,
  description text not null
);

insert into vocab.source_category (code, description) values
  ('general_transfer', 'General college transfer, not a specific alternative-credit product.'),
  ('ace_recommended_noncollegiate', 'Noncollegiate learning with an ACE recommendation.'),
  ('nccrs_recommended_noncollegiate', 'Noncollegiate learning with an NCCRS recommendation.'),
  ('ace_or_nccrs_recommended_noncollegiate', 'ACE or NCCRS recommended noncollegiate learning.'),
  ('ace_nccrs_exams_and_related', 'The source groups ACE/NCCRS-evaluated providers, exams, and related sources.'),
  ('exam', 'Examination credit.'),
  ('military', 'Military learning.'),
  ('portfolio', 'Portfolio assessment.'),
  ('certification_or_workforce', 'Certification or workforce training.'),
  ('two_year_institution', 'Credit from a two-year institution.'),
  ('four_year_institution', 'Credit from a four-year institution.'),
  ('alternative_provider_partner', 'Named alternative-credit partner policy.'),
  ('unspecified', 'Category not specified.');

create table vocab.requirement_area (
  code text primary key,
  description text not null
);

insert into vocab.requirement_area (code, description) values
  ('total', 'Total degree credits.'),
  ('residency', 'Institutional residency.'),
  ('general_education', 'General education.'),
  ('major', 'Major or core.'),
  ('concentration', 'Concentration.'),
  ('elective', 'Elective.'),
  ('upper_division', 'Upper-division credit.'),
  ('communication', 'Communication requirement.'),
  ('unspecified', 'Area not specified.');

create table vocab.equivalency_type (
  code text primary key,
  description text not null
);

insert into vocab.equivalency_type (code, description) values
  ('direct_course', 'Mapped to a specific destination course. Requires a destination course version.'),
  ('subject_elective', 'Subject elective.'),
  ('general_elective', 'General elective.'),
  ('general_education', 'Published as general-education credit. This is still not proof that a particular degree requirement is satisfied.'),
  ('major_requirement', 'Published against a major requirement. Still not a full degree audit.'),
  ('concentration_requirement', 'Published against a concentration requirement.'),
  ('manual_review', 'The institution requires a manual review rather than publishing an equivalency.');

create table vocab.provider_type (
  code text primary key,
  description text not null
);

insert into vocab.provider_type (code, description) values
  ('alternative_credit_provider', 'Alternative-credit or noncollegiate course provider.'),
  ('exam_board', 'Examination board. Exam rows are deferred; the type is reserved.'),
  ('workforce_training', 'Workforce or certification provider.'),
  ('other', 'Another provider type.');

create table vocab.provider_link_relationship (
  code text primary key,
  description text not null
);

insert into vocab.provider_link_relationship (code, description) values
  ('addresses', 'The policy mentions or addresses the provider. This is not acceptance.'),
  ('accepts', 'The policy explicitly accepts the provider, possibly with conditions.'),
  ('rejects', 'The policy explicitly rejects the provider.'),
  ('eligible_method', 'The provider is listed as an eligible method, still subject to the fact''s conditions.');

create table vocab.research_gap_status (
  code text primary key,
  description text not null
);

insert into vocab.research_gap_status (code, description) values
  ('open', 'Unresolved.'),
  ('in_review', 'Someone is resolving it.'),
  ('blocked', 'Blocked on a source or decision.'),
  ('resolved', 'Resolved. The canonical fact should now carry the answer.');

create table vocab.delivery_modality (
  code text primary key,
  description text not null
);

insert into vocab.delivery_modality (code, description) values
  ('online', 'Online.'),
  ('campus', 'Campus-based.'),
  ('hybrid', 'Hybrid.'),
  ('unknown', 'Modality not established.');

create table vocab.relationship_type (
  code text primary key,
  description text not null
);

insert into vocab.relationship_type (code, description) values
  ('successor_of', 'The from-institution is the successor of the to-institution.'),
  ('merged_into', 'Merged into the other institution.'),
  ('system_member', 'Member of a university system.'),
  ('acquired_by', 'Acquired by the other institution.'),
  ('other', 'Another relationship.');

create table vocab.limit_unit (
  code text primary key,
  description text not null
);

insert into vocab.limit_unit (code, description) values
  ('semester_credit', 'Semester credits.'),
  ('quarter_credit', 'Quarter credits.'),
  ('credits_unspecified', 'The source said credits without naming semester or quarter. Do not convert.'),
  ('percent', 'Percent of a requirement.'),
  ('courses', 'A count of courses.');
