export type TemporalCoverage = "match" | "ambiguous" | "out" | "undated" | "current_view";

export type VerificationStatus =
  | "unknown"
  | "unreviewed"
  | "machine_extracted"
  | "needs_review"
  | "source_confirmed"
  | "verified"
  | "institution_confirmed"
  | "conflicting_sources"
  | "stale"
  | "expired"
  | "superseded"
  | "inferred";

export type EnvelopeMeta = {
  api_version: "v1";
  policy_as_of: string | null;
  as_of_interpretation: "current_non_superseded_records" | "valid_time_inclusive";
  data_snapshot_at: string;
  credit_units_note: string;
};

export type Page = {
  limit: number;
  offset: number;
  total: number;
  next_offset?: number | null;
};

export type Temporal = {
  valid_from: string | null;
  valid_to: string | null;
  from_precision: string;
  to_precision: string;
  valid_from_display: string | null;
  valid_to_display: string | null;
  coverage: TemporalCoverage;
  recorded_at: string;
  superseded_at: string | null;
  as_of_interpretation: "valid_time_inclusive";
};

export type ProvenanceLink = {
  link_role: string;
  publisher: string | null;
  confidence: string;
  source_url: string | null;
  archive_url: string | null;
  evidence_id: string;
  page_number: number | null;
  source_type: string;
  published_at: string | null;
  retrieved_at: string;
  source_title: string;
  authority_scope: string | null;
  section_locator: string | null;
  evidence_excerpt: string | null;
  evidence_summary: string;
  extraction_method: string;
  source_document_id: string;
  verification_status: VerificationStatus;
};

export type InstitutionSearchHit = {
  id: string;
  official_name: string;
  institution_type: string;
  country_code: string;
  control: string | null;
  current_status: string;
  website_url: string | null;
  match_score: number;
};

export type InstitutionProfile = {
  id: string;
  official_name: string;
  display_name: string;
  display_name_basis: string;
  also_matching_names: string[];
  institution_type: string;
  country_code: string;
  control: string | null;
  current_status: string;
  current_status_meaning: string;
  website_url: string | null;
  notes: string | null;
  external_identifiers_status: "not_documented" | string;
  unknowns: string[];
  identifiers: unknown[];
  aliases: {
    id: string;
    alias: string;
    alias_type: string;
    verification_status: VerificationStatus;
    confidence: string;
    temporal: Temporal;
  }[];
  status_as_of: {
    status: string;
    basis: string;
    notes: string | null;
    temporal: Temporal | null;
    verification_status?: VerificationStatus;
  }[];
  accreditation: {
    applied: AccreditationRow[];
    not_applied_to_as_of: AccreditationRow[];
    history: AccreditationRow[] | null;
    history_included: boolean;
  };
  program_count: number;
  provenance?: ProvenanceLink[];
};

export type AccreditationRow = {
  id: string;
  accreditor_id: string;
  accreditor_name: string;
  accreditor_acronym: string | null;
  accreditation_status: string;
  accreditation_scope: string;
  historical_classification_label: string | null;
  program_id: string | null;
  notes: string | null;
  verification_status: VerificationStatus;
  confidence: string;
  temporal: Temporal;
};

export type PolicyFact = {
  policy_fact_id: string;
  policy_id: string;
  policy_version_id: string;
  policy_kind: string;
  title: string;
  fact_kind: string;
  statement: string;
  comparison: string | null;
  limit_value: number | null;
  limit_unit: string | null;
  limit_is_percentage: boolean;
  context_value: number | null;
  context_label: string | null;
  acceptance_status: string | null;
  acceptance_strength: string;
  establishes_course_acceptance: boolean;
  provider_links: { provider_id: string; provider_name: string; relationship: string }[];
  temporal: Temporal;
  provenance?: ProvenanceLink[];
  verification_status: VerificationStatus;
  confidence: string;
};

export type DegreeApplicability = {
  general_education: "not_documented";
  elective: "not_documented";
  major: "not_documented";
  concentration: "not_documented";
  residency: "not_documented";
  upper_division: "not_documented";
  total_degree_credits: "not_documented";
};

export type TransferEvaluation = {
  destination_institution_id: string;
  completed_on: string;
  policy_as_of: string;
  learning_experience_version_id: string;
  provider_id: string;
  distinctions: {
    credit_recommended: boolean | "not_documented" | "ambiguous";
    institution_accepts: string;
    acceptance_established: boolean;
    equivalency_documented: boolean;
    equivalency_type: string | null;
    degree_requirement_satisfied: "not_documented";
    degree_applicability: DegreeApplicability;
  };
  recommendations: {
    credit_recommendation_id: string;
    authority_identifier: string | null;
    recommended_credits: number | null;
    credit_unit: string | null;
    recommended_level: string | null;
    recommended_subject: string | null;
    recommendation_body: string;
    awards_credit: boolean;
    binds_destination_institutions: boolean;
    coverage: TemporalCoverage;
    temporal: Temporal;
    provenance: ProvenanceLink[];
  }[];
  policy_context: PolicyFact[];
  undated_policy_context: PolicyFact[];
  equivalencies: unknown[];
  requirement_bindings_touched: number;
  warnings: string[];
};

export type ApiEnvelope<T> = {
  meta: EnvelopeMeta;
  data: T;
  page?: Page;
};

export type ApiError = {
  error: {
    code: string;
    message: string;
  };
};
