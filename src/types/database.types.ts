/**
 * Application-facing row shapes for the Education Data Core.
 * Canonical identity is a UUID. External identifiers live on catalog.institution_identifiers.
 * Null means the source did not establish the value.
 */

export type Uuid = string;
export type IsoDate = string;
export type IsoTimestamp = string;

export type InstitutionRow = {
  id: Uuid;
  official_name: string;
  normalized_name: string;
  institution_type: string;
  country_code: string;
  control: string | null;
  current_status: string;
  website_url: string | null;
  notes: string | null;
  created_at: IsoTimestamp;
  updated_at: IsoTimestamp;
};

export type InstitutionAliasRow = {
  id: Uuid;
  institution_id: Uuid;
  alias: string;
  normalized_alias: string;
  alias_type: string;
  valid_from: IsoDate | null;
  valid_to: IsoDate | null;
  from_precision: string;
  to_precision: string;
  source_document_id: Uuid | null;
  verification_status: string;
  confidence: string;
  recorded_at: IsoTimestamp;
  superseded_at: IsoTimestamp | null;
};

export type InstitutionIdentifierRow = {
  id: Uuid;
  institution_id: Uuid;
  identifier_type: string;
  identifier_value: string;
  issuer: string;
  valid_from: IsoDate | null;
  valid_to: IsoDate | null;
  from_precision: string;
  to_precision: string;
  source_document_id: Uuid | null;
  verification_status: string;
  confidence: string;
};

export type InstitutionAccreditationRow = {
  id: Uuid;
  institution_id: Uuid;
  accreditor_id: Uuid;
  program_id: Uuid | null;
  accreditation_status: string;
  accreditation_scope: string;
  historical_classification_label: string | null;
  valid_from: IsoDate | null;
  valid_to: IsoDate | null;
  from_precision: string;
  to_precision: string;
  source_document_id: Uuid;
  verification_status: string;
  confidence: string;
  notes: string | null;
  superseded_at: IsoTimestamp | null;
};

export type ProgramVersionRow = {
  id: Uuid;
  program_id: Uuid;
  official_program_name: string;
  total_credits: number | null;
  credit_unit: string | null;
  academic_catalog_year: string | null;
  delivery_modality: string | null;
  status: string;
  valid_from: IsoDate | null;
  valid_to: IsoDate | null;
  verification_status: string;
  confidence: string;
};

export type CreditRecommendationRow = {
  id: Uuid;
  learning_experience_version_id: Uuid;
  recommendation_body_id: Uuid;
  authority_identifier: string | null;
  recommended_credits: number | null;
  credit_unit: string | null;
  recommended_level: string | null;
  recommended_subject: string | null;
  recommendation_start: IsoDate;
  recommendation_end: IsoDate | null;
  start_precision: string;
  end_precision: string;
  source_document_id: Uuid;
  verification_status: string;
  confidence: string;
  superseded_at: IsoTimestamp | null;
};

export type PolicyFactRow = {
  id: Uuid;
  policy_version_id: Uuid;
  fact_kind: string;
  comparison: string | null;
  limit_value: number | null;
  limit_unit: string | null;
  context_value: number | null;
  context_label: string | null;
  grade_threshold: string | null;
  acceptance_status: string | null;
  acceptance_strength: string;
  establishes_course_acceptance: boolean;
  statement: string;
  source_document_id: Uuid;
  verification_status: string;
  confidence: string;
  superseded_at: IsoTimestamp | null;
};

export type CourseEquivalencyRow = {
  id: Uuid;
  source_experience_version_id: Uuid | null;
  source_course_version_id: Uuid | null;
  destination_institution_id: Uuid;
  destination_course_version_id: Uuid | null;
  program_version_id: Uuid | null;
  equivalency_type: string;
  destination_credits: number | null;
  credit_unit: string | null;
  valid_from: IsoDate | null;
  valid_to: IsoDate | null;
  source_document_id: Uuid;
  verification_status: string;
  confidence: string;
  notes: string | null;
  superseded_at: IsoTimestamp | null;
};

export type SourceDocumentRow = {
  id: Uuid;
  source_url: string | null;
  source_title: string;
  source_type: string;
  publisher: string | null;
  authority_scope: string | null;
  published_at: IsoDate | null;
  retrieved_at: IsoTimestamp;
  extraction_method: string;
};

export type Database = {
  catalog: {
    institutions: InstitutionRow;
    institution_aliases: InstitutionAliasRow;
    institution_identifiers: InstitutionIdentifierRow;
    institution_accreditations: InstitutionAccreditationRow;
  };
  academic: {
    program_versions: ProgramVersionRow;
  };
  alternative: {
    credit_recommendations: CreditRecommendationRow;
  };
  policy: {
    policy_facts: PolicyFactRow;
  };
  transfer: {
    course_equivalencies: CourseEquivalencyRow;
  };
  provenance: {
    source_documents: SourceDocumentRow;
  };
};
