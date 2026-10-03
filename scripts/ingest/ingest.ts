import { createHash, randomUUID } from "node:crypto";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const NAMESPACE = "8c1d1a4e-5b2f-4c3a-9e7d-6f0a1b2c3d4e";

export function uuidV5(name: string, namespace = NAMESPACE): string {
  const namespaceBytes = Buffer.from(namespace.replace(/-/g, ""), "hex");
  const hash = createHash("sha1").update(namespaceBytes).update(name, "utf8").digest();
  const bytes = Buffer.from(hash.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function idFor(kind: string, key: string): string {
  return uuidV5(`${kind}:${key}`);
}

type EvidenceInput = {
  source_key: string;
  summary: string;
  excerpt?: string | null;
  role?: string;
  section?: string | null;
  page?: number | null;
  verification_status?: string;
  confidence?: string;
};

type SourceInput = {
  key: string;
  source_url?: string | null;
  source_title: string;
  source_type: string;
  publisher?: string | null;
  authority_scope?: string | null;
  published_at?: string | null;
  retrieved_at: string;
  effective_from?: string | null;
  effective_to?: string | null;
  academic_year?: string | null;
  archive_url?: string | null;
  extraction_method: string;
  notes?: string | null;
};

async function upsert(
  client: pg.Client,
  table: string,
  row: Record<string, unknown>,
): Promise<void> {
  const columns = Object.keys(row);
  const mutable = columns.filter((column) => column !== "id");
  const distinct = mutable
    .map((column) => `${table}.${column} is distinct from excluded.${column}`)
    .join(" or ");
  const sql = `
    insert into ${table} (${columns.join(", ")})
    values (${columns.map((_, index) => `$${index + 1}`).join(", ")})
    on conflict (id) do update set
      ${mutable.map((column) => `${column} = excluded.${column}`).join(", ")}
    where ${distinct}
  `;
  await client.query(sql, columns.map((column) => row[column]));
}

async function linkEvidence(
  client: pg.Client,
  factKey: string,
  factSchema: string,
  factTable: string,
  factId: string,
  evidence: EvidenceInput[] | undefined,
): Promise<void> {
  for (const [index, item] of (evidence ?? []).entries()) {
    const evidenceId = idFor("evidence", `${factKey}:${index}`);
    await upsert(client, "provenance.evidence", {
      id: evidenceId,
      source_document_id: idFor("source", item.source_key),
      page_number: item.page ?? null,
      section_locator: item.section ?? null,
      evidence_summary: item.summary,
      evidence_excerpt: item.excerpt ?? null,
      evidence_role: item.role ?? "supports",
      extraction_method: "deep_research_report",
      verification_status: item.verification_status ?? "source_confirmed",
      confidence: item.confidence ?? "high",
      manually_verified: false,
    });
    await upsert(client, "provenance.fact_evidence_links", {
      id: idFor("evidence-link", `${factKey}:${index}`),
      evidence_id: evidenceId,
      fact_schema: factSchema,
      fact_table: factTable,
      fact_id: factId,
      link_role: item.role ?? "supports",
    });
  }
}

function autoEvidence(
  sourceKey: string | null | undefined,
  summary: string | null | undefined,
  verificationStatus: string,
  confidence: string,
  explicit?: EvidenceInput[],
): EvidenceInput[] | undefined {
  if (explicit && explicit.length > 0) return explicit;
  if (!sourceKey || !summary) return undefined;
  return [{
    source_key: sourceKey,
    summary,
    verification_status: verificationStatus,
    confidence,
  }];
}

export async function runIngest(databaseUrl: string, extractPath: string): Promise<Record<string, number>> {
  const raw = await readFile(extractPath, "utf8");
  const payload = JSON.parse(raw) as {
    sources: SourceInput[];
    recommendation_bodies: Array<Record<string, unknown>>;
    accreditors: Array<Record<string, unknown>>;
    accreditor_recognition: Array<Record<string, unknown>>;
    providers: Array<Record<string, unknown>>;
    institutions: Array<Record<string, unknown>>;
    learning_experiences: Array<Record<string, unknown>>;
    programs: Array<Record<string, unknown>>;
    policies: Array<Record<string, unknown>>;
    research_gaps: Array<Record<string, unknown>>;
  };
  const hash = createHash("sha256").update(raw).digest("hex");
  const client = new pg.Client({ connectionString: databaseUrl });
  await client.connect();
  const batchId = randomUUID();
  try {
    await client.query("begin");
    await client.query(
      `insert into internal.import_batches
        (id, source_family, status, payload_sha256, records_read)
       values ($1, 'v1_research_extract', 'running', $2, $3)`,
      [batchId, hash, raw.length],
    );
    await client.query(
      `insert into raw.source_payloads
        (id, source_family, payload, payload_sha256, retrieved_at)
       values ($1, 'v1_research_extract', $2::jsonb, $3, $4)
       on conflict (source_family, payload_sha256) do nothing`,
      [idFor("payload", hash), payload, hash, "2026-10-03T00:00:00Z"],
    );

    for (const source of payload.sources) {
      await upsert(client, "provenance.source_documents", {
        id: idFor("source", source.key),
        source_key: source.key,
        source_url: source.source_url ?? null,
        source_title: source.source_title,
        source_type: source.source_type,
        publisher: source.publisher ?? null,
        authority_scope: source.authority_scope ?? null,
        published_at: source.published_at ?? null,
        retrieved_at: source.retrieved_at,
        effective_from: source.effective_from ?? null,
        effective_to: source.effective_to ?? null,
        academic_year: source.academic_year ?? null,
        archive_url: source.archive_url ?? null,
        extraction_method: source.extraction_method,
        notes: source.notes ?? null,
      });
    }

    for (const body of payload.recommendation_bodies) {
      const key = String(body.key);
      const rowId = idFor("recommendation-body", key);
      await upsert(client, "alternative.recommendation_bodies", {
        id: rowId,
        code: body.code,
        official_name: body.official_name,
        awards_credit: body.awards_credit,
        binds_destination_institutions: body.binds_destination_institutions,
        notes: body.notes ?? null,
      });
      await linkEvidence(
        client,
        key,
        "alternative",
        "recommendation_bodies",
        rowId,
        body.evidence as EvidenceInput[] | undefined,
      );
    }

    for (const accreditor of payload.accreditors) {
      const key = String(accreditor.key);
      const rowId = idFor("accreditor", key);
      await upsert(client, "catalog.accreditors", {
        id: rowId,
        official_name: accreditor.official_name,
        acronym: accreditor.acronym ?? null,
        normalized_name: String(accreditor.normalized_name),
        accreditor_scope: accreditor.accreditor_scope,
        website_url: accreditor.website_url ?? null,
        notes: accreditor.notes ?? null,
      });
      await linkEvidence(
        client,
        key,
        "catalog",
        "accreditors",
        rowId,
        accreditor.evidence as EvidenceInput[] | undefined,
      );
    }

    for (const recognition of payload.accreditor_recognition) {
      const key = String(recognition.key);
      const rowId = idFor("accreditor-recognition", key);
      await upsert(client, "catalog.accreditor_recognition_history", {
        id: rowId,
        accreditor_id: idFor("accreditor", String(recognition.accreditor_key)),
        recognition_authority: recognition.recognition_authority,
        status: recognition.status,
        valid_from: recognition.valid_from ?? null,
        valid_to: recognition.valid_to ?? null,
        from_precision: recognition.from_precision ?? "unknown",
        to_precision: recognition.to_precision ?? "unknown",
        notes: recognition.notes ?? null,
        source_document_id: idFor("source", String(recognition.source_key)),
        verification_status: recognition.verification_status,
        confidence: recognition.confidence,
      });
      await linkEvidence(
        client,
        key,
        "catalog",
        "accreditor_recognition_history",
        rowId,
        autoEvidence(
          String(recognition.source_key),
          String(recognition.notes ?? recognition.status),
          String(recognition.verification_status),
          String(recognition.confidence),
          recognition.evidence as EvidenceInput[] | undefined,
        ),
      );
    }

    for (const provider of payload.providers) {
      const key = String(provider.key);
      const rowId = idFor("provider", key);
      await upsert(client, "alternative.providers", {
        id: rowId,
        official_name: provider.official_name,
        normalized_name: String(provider.normalized_name),
        provider_type: provider.provider_type,
        website_url: provider.website_url ?? null,
        notes: provider.notes ?? null,
        source_document_id: idFor("source", String(provider.source_key)),
        verification_status: provider.verification_status,
        confidence: provider.confidence,
      });
      await linkEvidence(
        client,
        key,
        "alternative",
        "providers",
        rowId,
        autoEvidence(
          String(provider.source_key),
          String(provider.notes ?? provider.official_name),
          String(provider.verification_status),
          String(provider.confidence),
          provider.evidence as EvidenceInput[] | undefined,
        ),
      );
    }

    for (const institution of payload.institutions) {
      const key = String(institution.key);
      const rowId = idFor("institution", key);
      await upsert(client, "catalog.institutions", {
        id: rowId,
        official_name: institution.official_name,
        normalized_name: String(institution.normalized_name),
        institution_type: institution.institution_type,
        country_code: institution.country_code ?? "US",
        control: institution.control ?? null,
        current_status: institution.current_status,
        website_url: institution.website_url ?? null,
        notes: institution.notes ?? null,
      });
      await linkEvidence(
        client,
        key,
        "catalog",
        "institutions",
        rowId,
        institution.evidence as EvidenceInput[] | undefined,
      );

      for (const alias of (institution.aliases as Array<Record<string, unknown>> | undefined) ?? []) {
        const aliasKey = String(alias.key);
        const aliasId = idFor("alias", aliasKey);
        await upsert(client, "catalog.institution_aliases", {
          id: aliasId,
          institution_id: rowId,
          alias: alias.alias,
          normalized_alias: String(alias.normalized_alias),
          alias_type: alias.alias_type,
          valid_from: alias.valid_from ?? null,
          valid_to: alias.valid_to ?? null,
          from_precision: alias.from_precision ?? "unknown",
          to_precision: alias.to_precision ?? "unknown",
          source_document_id: alias.source_key ? idFor("source", String(alias.source_key)) : null,
          verification_status: alias.verification_status,
          confidence: alias.confidence,
        });
        await linkEvidence(
          client,
          aliasKey,
          "catalog",
          "institution_aliases",
          aliasId,
          alias.evidence as EvidenceInput[] | undefined,
        );
      }

      for (const status of (institution.status_versions as Array<Record<string, unknown>> | undefined) ?? []) {
        const statusKey = String(status.key);
        const statusId = idFor("status", statusKey);
        await upsert(client, "catalog.institution_status_versions", {
          id: statusId,
          institution_id: rowId,
          status: status.status,
          valid_from: status.valid_from ?? null,
          valid_to: status.valid_to ?? null,
          from_precision: status.from_precision ?? "unknown",
          to_precision: status.to_precision ?? "unknown",
          notes: status.notes ?? null,
          source_document_id: idFor("source", String(status.source_key)),
          verification_status: status.verification_status,
          confidence: status.confidence,
        });
        await linkEvidence(
          client,
          statusKey,
          "catalog",
          "institution_status_versions",
          statusId,
          autoEvidence(
            String(status.source_key),
            String(status.notes ?? status.status),
            String(status.verification_status),
            String(status.confidence),
            status.evidence as EvidenceInput[] | undefined,
          ),
        );
      }

      for (const accreditation of (institution.accreditations as Array<Record<string, unknown>> | undefined) ?? []) {
        const accreditationKey = String(accreditation.key);
        const accreditationId = idFor("accreditation", accreditationKey);
        await upsert(client, "catalog.institution_accreditations", {
          id: accreditationId,
          institution_id: rowId,
          accreditor_id: idFor("accreditor", String(accreditation.accreditor_key)),
          program_id: accreditation.program_key
            ? idFor("program", String(accreditation.program_key))
            : null,
          accreditation_status: accreditation.accreditation_status,
          accreditation_scope: accreditation.accreditation_scope,
          historical_classification_label: accreditation.historical_classification_label ?? null,
          valid_from: accreditation.valid_from ?? null,
          valid_to: accreditation.valid_to ?? null,
          from_precision: accreditation.from_precision ?? "unknown",
          to_precision: accreditation.to_precision ?? "unknown",
          notes: accreditation.notes ?? null,
          source_document_id: idFor("source", String(accreditation.source_key)),
          verification_status: accreditation.verification_status,
          confidence: accreditation.confidence,
        });
        await linkEvidence(
          client,
          accreditationKey,
          "catalog",
          "institution_accreditations",
          accreditationId,
          autoEvidence(
            String(accreditation.source_key),
            String(accreditation.notes ?? accreditation.accreditation_status),
            String(accreditation.verification_status),
            String(accreditation.confidence),
            accreditation.evidence as EvidenceInput[] | undefined,
          ),
        );
      }
    }

    for (const experience of payload.learning_experiences) {
      const key = String(experience.key);
      const rowId = idFor("learning-experience", key);
      await upsert(client, "alternative.learning_experiences", {
        id: rowId,
        provider_id: idFor("provider", String(experience.provider_key)),
        provider_course_identifier: experience.provider_course_identifier ?? null,
        identifier_status: experience.identifier_status ?? "published",
        canonical_title: experience.canonical_title,
        normalized_title: String(experience.normalized_title),
      });
      const version = experience.version as Record<string, unknown>;
      const versionKey = String(version.key);
      const versionId = idFor("learning-experience-version", versionKey);
      await upsert(client, "alternative.learning_experience_versions", {
        id: versionId,
        learning_experience_id: rowId,
        official_title: version.official_title,
        description: version.description ?? null,
        subject: version.subject ?? null,
        passing_threshold: version.passing_threshold ?? null,
        valid_from: version.valid_from ?? null,
        valid_to: version.valid_to ?? null,
        from_precision: version.from_precision ?? "unknown",
        to_precision: version.to_precision ?? "unknown",
        source_document_id: version.source_key ? idFor("source", String(version.source_key)) : null,
        verification_status: version.verification_status,
        confidence: version.confidence,
      });
      await linkEvidence(
        client,
        versionKey,
        "alternative",
        "learning_experience_versions",
        versionId,
        version.evidence as EvidenceInput[] | undefined,
      );
      const recommendation = experience.recommendation as Record<string, unknown> | null;
      if (recommendation) {
        const recommendationKey = String(recommendation.key);
        const recommendationId = idFor("credit-recommendation", recommendationKey);
        await upsert(client, "alternative.credit_recommendations", {
          id: recommendationId,
          learning_experience_version_id: versionId,
          recommendation_body_id: idFor("recommendation-body", String(recommendation.body_key)),
          authority_identifier: recommendation.authority_identifier ?? null,
          recommendation_version: recommendation.recommendation_version ?? null,
          recommended_credits: recommendation.recommended_credits ?? null,
          credit_unit: recommendation.credit_unit ?? null,
          recommended_level: recommendation.recommended_level ?? null,
          recommended_subject: recommendation.recommended_subject ?? null,
          recommendation_start: recommendation.recommendation_start,
          recommendation_end: recommendation.recommendation_end ?? null,
          start_precision: recommendation.start_precision ?? "day",
          end_precision: recommendation.end_precision ?? "day",
          recommendation_notes: recommendation.recommendation_notes ?? null,
          source_document_id: idFor("source", String(recommendation.source_key)),
          verification_status: recommendation.verification_status,
          confidence: recommendation.confidence,
        });
        await linkEvidence(
          client,
          recommendationKey,
          "alternative",
          "credit_recommendations",
          recommendationId,
          recommendation.evidence as EvidenceInput[] | undefined,
        );
      }
    }

    for (const program of payload.programs) {
      const key = String(program.key);
      const rowId = idFor("program", key);
      await upsert(client, "academic.programs", {
        id: rowId,
        institution_id: idFor("institution", String(program.institution_key)),
        official_program_family_name: program.official_program_family_name,
        normalized_name: String(program.normalized_name),
        program_category: program.program_category,
        degree_type: program.degree_type,
        cip_code: program.cip_code ?? null,
      });
      const version = program.version as Record<string, unknown>;
      const versionKey = String(version.key);
      const versionId = idFor("program-version", versionKey);
      await upsert(client, "academic.program_versions", {
        id: versionId,
        program_id: rowId,
        version_label: version.version_label ?? null,
        academic_catalog_year: version.academic_catalog_year ?? null,
        official_program_name: version.official_program_name,
        total_credits: version.total_credits ?? null,
        credit_unit: version.credit_unit ?? null,
        delivery_modality: version.delivery_modality ?? null,
        status: version.status ?? "unknown",
        valid_from: version.valid_from ?? null,
        valid_to: version.valid_to ?? null,
        from_precision: version.from_precision ?? "unknown",
        to_precision: version.to_precision ?? "unknown",
        source_document_id: version.source_key ? idFor("source", String(version.source_key)) : null,
        verification_status: version.verification_status,
        confidence: version.confidence,
      });
      await linkEvidence(
        client,
        versionKey,
        "academic",
        "program_versions",
        versionId,
        version.evidence as EvidenceInput[] | undefined,
      );
    }

    for (const policy of payload.policies) {
      const key = String(policy.key);
      const policyId = idFor("policy", key);
      await upsert(client, "policy.policies", {
        id: policyId,
        institution_id: idFor("institution", String(policy.institution_key)),
        program_id: policy.program_key ? idFor("program", String(policy.program_key)) : null,
        policy_kind: policy.policy_kind,
        title: policy.title,
      });
      const version = policy.version as Record<string, unknown>;
      const versionKey = String(version.key);
      const versionId = idFor("policy-version", versionKey);
      await upsert(client, "policy.policy_versions", {
        id: versionId,
        policy_id: policyId,
        version_label: version.version_label ?? null,
        academic_catalog_year: version.academic_catalog_year ?? null,
        valid_from: version.valid_from ?? null,
        valid_to: version.valid_to ?? null,
        from_precision: version.from_precision ?? "unknown",
        to_precision: version.to_precision ?? "unknown",
        published_at: version.published_at ?? null,
        source_document_id: idFor("source", String(version.source_key)),
        verification_status: version.verification_status,
        confidence: version.confidence,
        notes: version.notes ?? null,
      });
      await linkEvidence(
        client,
        versionKey,
        "policy",
        "policy_versions",
        versionId,
        autoEvidence(
          String(version.source_key),
          String(version.notes ?? version.version_label ?? policy.title),
          String(version.verification_status),
          String(version.confidence),
          version.evidence as EvidenceInput[] | undefined,
        ),
      );
      for (const fact of policy.facts as Array<Record<string, unknown>>) {
        const factKey = String(fact.key);
        const factId = idFor("policy-fact", factKey);
        await upsert(client, "policy.policy_facts", {
          id: factId,
          policy_version_id: versionId,
          fact_kind: fact.fact_kind,
          scope_degree_type: fact.scope_degree_type ?? null,
          scope_modality: fact.scope_modality ?? null,
          scope_career: fact.scope_career ?? null,
          scope_requirement_area: fact.scope_requirement_area ?? null,
          source_category: fact.source_category ?? null,
          method_labels: fact.method_labels ?? null,
          comparison: fact.comparison ?? null,
          limit_value: fact.limit_value ?? null,
          limit_unit: fact.limit_unit ?? null,
          limit_is_percentage: fact.limit_is_percentage ?? false,
          context_value: fact.context_value ?? null,
          context_label: fact.context_label ?? null,
          grade_threshold: fact.grade_threshold ?? null,
          course_age_value: fact.course_age_value ?? null,
          course_age_unit: fact.course_age_unit ?? null,
          acceptance_status: fact.acceptance_status ?? null,
          acceptance_strength: fact.acceptance_strength ?? "none",
          establishes_course_acceptance: fact.establishes_course_acceptance ?? false,
          statement: fact.statement,
          source_document_id: idFor("source", String(fact.source_key)),
          verification_status: fact.verification_status,
          confidence: fact.confidence,
        });
        await linkEvidence(
          client,
          factKey,
          "policy",
          "policy_facts",
          factId,
          autoEvidence(
            String(fact.source_key),
            String(fact.statement),
            String(fact.verification_status),
            String(fact.confidence),
            fact.evidence as EvidenceInput[] | undefined,
          ),
        );
        for (const link of (fact.provider_links as Array<Record<string, unknown>> | undefined) ?? []) {
          await client.query(
            `insert into policy.policy_fact_providers (policy_fact_id, provider_id, relationship)
             values ($1, $2, $3)
             on conflict (policy_fact_id, provider_id) do update
             set relationship = excluded.relationship
             where policy.policy_fact_providers.relationship is distinct from excluded.relationship`,
            [factId, idFor("provider", String(link.provider_key)), link.relationship],
          );
        }
      }
    }

    for (const gap of payload.research_gaps) {
      const key = String(gap.key);
      await upsert(client, "provenance.research_gaps", {
        id: idFor("research-gap", key),
        institution_id: gap.institution_key ? idFor("institution", String(gap.institution_key)) : null,
        entity_type: gap.entity_type ?? null,
        entity_id: gap.entity_key ? idFor(String(gap.entity_kind ?? "institution"), String(gap.entity_key)) : null,
        topic: gap.topic,
        unresolved_question: gap.unresolved_question,
        conflicting_evidence: gap.conflicting_evidence ?? null,
        current_best_evidence: gap.current_best_evidence ?? null,
        confidence: gap.confidence ?? null,
        recommended_action: gap.recommended_action ?? null,
        status: gap.status ?? "open",
        resolved_at: null,
      });
    }

    await client.query("select api.rebuild_search_documents()");

    const countsResult = await client.query(`
      select 'institutions' as entity, count(*)::int as n from catalog.institutions
      union all select 'aliases', count(*)::int from catalog.institution_aliases
      union all select 'identifiers', count(*)::int from catalog.institution_identifiers
      union all select 'accreditors', count(*)::int from catalog.accreditors
      union all select 'accreditations', count(*)::int from catalog.institution_accreditations
      union all select 'providers', count(*)::int from alternative.providers
      union all select 'learning_experiences', count(*)::int from alternative.learning_experiences
      union all select 'credit_recommendations', count(*)::int from alternative.credit_recommendations
      union all select 'programs', count(*)::int from academic.programs
      union all select 'policy_facts', count(*)::int from policy.policy_facts
      union all select 'equivalencies', count(*)::int from transfer.course_equivalencies
      union all select 'research_gaps', count(*)::int from provenance.research_gaps
      union all select 'sources', count(*)::int from provenance.source_documents
    `);
    const counts: Record<string, number> = {};
    for (const row of countsResult.rows) counts[row.entity] = row.n;

    await client.query(
      `update internal.import_batches
       set status = 'succeeded', finished_at = now(), records_upserted = $2, notes = $3
       where id = $1`,
      [batchId, counts.institutions ?? 0, JSON.stringify(counts)],
    );
    await client.query("commit");

    await mkdir(path.resolve("data/processed"), { recursive: true });
    await writeFile(
      path.resolve("data/processed/last_import_report.json"),
      JSON.stringify({ payload_sha256: hash, counts }, null, 2),
    );
    return counts;
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    await client.end();
  }
}

const invokedDirectly = process.argv[1]
  && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (invokedDirectly) {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    console.error("DATABASE_URL is required.");
    process.exit(1);
  }
  const extractPath = path.resolve("data/raw/v1_research_extract.json");
  const counts = await runIngest(databaseUrl, extractPath);
  console.log(JSON.stringify(counts, null, 2));
}
