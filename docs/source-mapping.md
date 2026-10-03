# Source mapping

The only V1 seed file is `data/raw/v1_research_extract.json`. It was compiled from the Deep Research report verified on 2026-10-03. Ingestion copies that file into `raw.source_payloads` and upserts the tables below. A second run with the same bytes does not insert another payload (`unique (source_family, payload_sha256)`).

| Extract collection | Canonical destination | Notes |
| --- | --- | --- |
| `sources` | `provenance.source_documents` | 25 documents. The research report itself has a null URL and `authority_scope = discovery_only`. |
| evidence embedded on each fact | `provenance.evidence`, `provenance.fact_evidence_links` | Generated when a statement has no separate evidence array. |
| `recommendation_bodies` | `alternative.recommendation_bodies` | ACE and NCCRS. Both `awards_credit` and `binds_destination_institutions` are false. |
| `accreditors` | `catalog.accreditors` | MSCHE, HLC, NECHE, WSCUC, ACICS, DEAC. Only DEAC has a website in the extract. |
| `accreditor_recognition` | `catalog.accreditor_recognition_history` | ED recognition where the extract established it. ACICS is terminated 2022-08-19. No DEAC recognition row. |
| `providers` | `alternative.providers` | Sophia Learning, Study.com, StraighterLine, Coopersmith Career Consulting. Websites were not captured. |
| `institutions` | `catalog.institutions` | 10 institutions. `control` is null on all of them. |
| `institutions[].aliases` | `catalog.institution_aliases` | 12 aliases, including dated former names. |
| `institutions[].identifiers` | `catalog.institution_identifiers` | Present in the model. The extract has none. |
| `institutions[].status` | `catalog.institution_status_versions` | ITT closed from 2016-09-06. No invented operating row before that date. |
| `institutions[].accreditations` | `catalog.institution_accreditations` | 8 rows. Excelsior and ITT have none. |
| `learning_experiences` | `alternative.learning_experiences`, `learning_experience_versions`, `credit_recommendations` | Two experiences. One ACE recommendation. |
| `programs` | `academic.programs`, `academic.program_versions` | Excelsior BS Health Sciences only. Totals and catalog year are null. Status is `unknown`, not assumed active. |
| `policies` | `policy.policies`, `policy.policy_versions`, `policy.policy_facts`, `policy.policy_fact_providers` | 16 facts. |
| `research_gaps` | `provenance.research_gaps` | 35 open gaps. Staff-only. |
| — | `transfer.course_equivalencies` | Not in the extract. Left empty. |
| — | `academic.requirement_nodes` | Not in the extract. Left empty. |
| — | `catalog.search_documents` | Derived on ingest by `api.rebuild_search_documents`. Rebuilt, not historically versioned. |

## Documents that support the loaded facts

Institution and policy pages used as sources include Excelsior's transfer-credit and university-designation pages, UMPI YourPace FAQs, UMass Global prior-learning and Brandman-transfer pages, Purdue Global military-spouse and 2018 commencement pages, TESU transfer FAQs and accreditation page, Capella, University of Phoenix, Charter Oak, and SNHU transfer pages.

Recommendation and recognition sources include the ACE National Guide and its granting/seeking pages, NCCRS pages for Coopersmith and evaluation publication, ED's accreditation and ACICS-termination pages, the ED ITT student notice, and DEAC's own site.

The ED proposed interpretive rule on the word "regional" is a source document so the catalog can refuse that label. It is not stored as an accreditation classification.

## What was not mapped because the extract did not establish it

UNITID, OPEID, and DAPIP identifiers. Excelsior's institutional accreditor. An ITT–ACICS grant. A Regents College alias. Penn Foster as an institution. Numeric Charter Oak maxima and grade thresholds. A SNHU 30-credit residency. Capella program totals in quarter credits as a converted semester number. Any course-to-course equivalency. Any statement that a degree requirement is satisfied.

Those absences are research gaps or null fields. They are not defaulted.
