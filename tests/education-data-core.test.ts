import assert from "node:assert/strict";
import test from "node:test";
import pg from "pg";
import { createApp } from "../src/server/app.ts";
import { loadEnvFile } from "../src/server/env.ts";
import { runIngest } from "../scripts/ingest/ingest.ts";

loadEnvFile();

const databaseUrl = process.env.DATABASE_URL;
const apiDatabaseUrl = process.env.API_DATABASE_URL;
if (!databaseUrl || !apiDatabaseUrl) {
  throw new Error("DATABASE_URL and API_DATABASE_URL are required.");
}

const admin = new pg.Pool({ connectionString: databaseUrl });
const apiPool = new pg.Pool({
  connectionString: apiDatabaseUrl,
  options: "-c role=edu_app",
});

async function one<T = Record<string, unknown>>(sql: string, params: unknown[] = []): Promise<T> {
  const result = await admin.query(sql, params);
  return result.rows[0] as T;
}

async function institutionId(name: string): Promise<string> {
  const row = await one<{ id: string }>(
    "select id from catalog.institutions where official_name = $1",
    [name],
  );
  assert.ok(row?.id, `missing institution ${name}`);
  return row.id;
}

test.after(async () => {
  await admin.end();
  await apiPool.end();
});

test("seed counts match the research extract", async () => {
  const row = await one<Record<string, string>>(`
    select
      (select count(*) from catalog.institutions) as institutions,
      (select count(*) from catalog.institution_aliases) as aliases,
      (select count(*) from catalog.institution_identifiers) as identifiers,
      (select count(*) from catalog.accreditors) as accreditors,
      (select count(*) from catalog.institution_accreditations) as accreditations,
      (select count(*) from alternative.providers) as providers,
      (select count(*) from alternative.learning_experiences) as learning_experiences,
      (select count(*) from alternative.credit_recommendations) as credit_recommendations,
      (select count(*) from academic.programs) as programs,
      (select count(*) from policy.policy_facts) as policy_facts,
      (select count(*) from transfer.course_equivalencies) as equivalencies,
      (select count(*) from provenance.research_gaps) as research_gaps,
      (select count(*) from provenance.source_documents) as sources
  `);
  assert.deepEqual(
    Object.fromEntries(Object.entries(row).map(([key, value]) => [key, Number(value)])),
    {
      institutions: 10,
      aliases: 12,
      identifiers: 0,
      accreditors: 6,
      accreditations: 8,
      providers: 4,
      learning_experiences: 2,
      credit_recommendations: 1,
      programs: 1,
      policy_facts: 16,
      equivalencies: 0,
      research_gaps: 35,
      sources: 25,
    },
  );
});

test("data-quality checks report no errors", async () => {
  const result = await admin.query(
    "select severity, count(*)::int as n from internal.run_data_quality_checks() group by severity",
  );
  const bySeverity = Object.fromEntries(result.rows.map((row) => [row.severity, row.n]));
  assert.equal(bySeverity.error ?? 0, 0);
  assert.equal(bySeverity.info, 2);
});

test("credit units are never treated as convertible", async () => {
  const row = await one<{
    semester_quarter: boolean;
    semester_unspecified: boolean;
    named_match: boolean;
    limit_units: boolean;
  }>(`
    select
      api.credits_are_comparable('semester', 'quarter') as semester_quarter,
      api.credits_are_comparable('semester', 'credits_unspecified') as semester_unspecified,
      api.credits_are_comparable('semester', 'semester') as named_match,
      api.credits_are_comparable('semester_credit', 'quarter_credit') as limit_units
  `);
  assert.equal(row.semester_quarter, false);
  assert.equal(row.semester_unspecified, false);
  assert.equal(row.named_match, true);
  assert.equal(row.limit_units, false);
});

test("search resolves abbreviations, former names, and providers", async () => {
  const tesu = await one<{ body: { data: { official_name: string }[] } }>(
    "select api.search_institutions('tesu', null, null, 5, 0) as body",
  );
  assert.equal(tesu.body.data[0]?.official_name, "Thomas Edison State University");

  const college = await one<{ body: { data: { official_name: string }[] } }>(
    "select api.search_institutions('excelsior college', null, null, 5, 0) as body",
  );
  assert.equal(college.body.data[0]?.official_name, "Excelsior University");

  const brandman = await one<{ body: { data: { official_name: string }[] } }>(
    "select api.search_institutions('brandman', null, null, 5, 0) as body",
  );
  assert.equal(brandman.body.data[0]?.official_name, "UMass Global");

  const presque = await one<{ body: { data: { official_name: string }[] } }>(
    "select api.search_institutions('presque isle', null, null, 5, 0) as body",
  );
  assert.equal(presque.body.data[0]?.official_name, "University of Maine at Presque Isle");

  const provider = await one<{ body: { data: { official_name: string }[] } }>(
    "select api.search_providers('straighter', 5, 0) as body",
  );
  assert.equal(provider.body.data[0]?.official_name, "StraighterLine");
});

test("Excelsior, Brandman, and ITT names and status follow valid time", async () => {
  const excelsior = await institutionId("Excelsior University");
  const college = await one<{ name: string }>(
    "select api.get_institution_profile($1, '2020-06-01', false)->'data'->>'display_name' as name",
    [excelsior],
  );
  const university = await one<{ name: string }>(
    "select api.get_institution_profile($1, '2022-08-01', false)->'data'->>'display_name' as name",
    [excelsior],
  );
  assert.equal(college.name, "Excelsior College");
  assert.equal(university.name, "Excelsior University");

  const umass = await institutionId("UMass Global");
  const before = await one<{ name: string }>(
    "select api.get_institution_profile($1, '2020-06-01', false)->'data'->>'display_name' as name",
    [umass],
  );
  const during = await one<{ name: string; basis: string }>(
    `select api.get_institution_profile($1, '2021-06-15', false)->'data'->>'display_name' as name,
            api.get_institution_profile($1, '2021-06-15', false)->'data'->>'display_name_basis' as basis`,
    [umass],
  );
  assert.equal(before.name, "Brandman University");
  assert.equal(during.name, "UMass Global");
  assert.equal(during.basis, "alias_ambiguous");

  const itt = await institutionId("ITT Technical Institute");
  const closedYear = await one<{ status: string }>(
    "select api.get_institution_profile($1, '2015-06-01', false)->'data'->'status_as_of'->0->>'status' as status",
    [itt],
  );
  const afterClose = await one<{ status: string }>(
    "select api.get_institution_profile($1, '2017-06-01', false)->'data'->'status_as_of'->0->>'status' as status",
    [itt],
  );
  const accreditation = await one<{ n: number }>(
    "select jsonb_array_length(api.get_institution_accreditation($1, null, false)->'data'->'applied') as n",
    [itt],
  );
  assert.equal(closedYear.status, "not_documented");
  assert.equal(afterClose.status, "closed");
  assert.equal(Number(accreditation.n), 0);
});

test("undated TESU accreditation is current-only and ACICS recognition is not an ITT grant", async () => {
  const tesu = await institutionId("Thomas Edison State University");
  const current = await one<{ n: number }>(
    "select jsonb_array_length(api.get_institution_accreditation($1, null, false)->'data'->'applied') as n",
    [tesu],
  );
  const historical = await one<{ applied: number; withheld: string }>(
    `select jsonb_array_length(body->'data'->'applied') as applied,
            body->'data'->'not_applied_to_as_of'->0->>'accreditor_acronym' as withheld
     from (select api.get_institution_accreditation($1, '2014-06-01', true) as body) q`,
    [tesu],
  );
  assert.equal(Number(current.n), 1);
  assert.equal(Number(historical.applied), 0);
  assert.equal(historical.withheld, "MSCHE");

  const acics = await one<{ status: string; valid_from: string; grants: string }>(`
    select r.status, r.valid_from::text,
           (select count(*) from catalog.institution_accreditations a
            join catalog.accreditors c on c.id = a.accreditor_id
            where c.acronym = 'ACICS')::text as grants
    from catalog.accreditor_recognition_history r
    join catalog.accreditors c on c.id = r.accreditor_id
    where c.acronym = 'ACICS'
  `);
  assert.equal(acics.status, "terminated");
  assert.equal(acics.valid_from, "2022-08-19");
  assert.equal(acics.grants, "0");

  const umpi = await institutionId("University of Maine at Presque Isle");
  const scope = await one<{ scope: string }>(
    "select api.get_institution_accreditation($1, null, false)->'data'->'applied'->0->>'accreditation_scope' as scope",
    [umpi],
  );
  assert.equal(scope.scope, "university_system_participation");
});

test("TESU transfer policy is dated and a recommendation does not accept credit", async () => {
  const tesu = await institutionId("Thomas Edison State University");
  const early = await one<{ n: number }>(
    `select jsonb_array_length(api.get_transfer_policy($1, '2020-06-01', null, false)->'data'->'applied') as n`,
    [tesu],
  );
  const later = await one<{ unit: string; accepts: boolean; value: string }>(
    `select fact->>'limit_unit' as unit,
            (fact->>'establishes_course_acceptance')::boolean as accepts,
            fact->>'limit_value' as value
     from jsonb_array_elements(api.get_transfer_policy($1, '2024-01-01', null, true)->'data'->'applied') fact
     where fact->>'fact_kind' = 'alternative_credit_limit'`,
    [tesu],
  );
  assert.equal(Number(early.n), 0);
  assert.equal(later.unit, "credits_unspecified");
  assert.equal(later.accepts, false);
  assert.equal(Number(later.value), 90);

  const evaluated = await one<{ body: { data: { distinctions: Record<string, unknown>; recommendations: { provenance: { source_url: string; retrieved_at: string; extraction_method: string; evidence_excerpt: string | null }[] }[] } } }>(
    "select api.evaluate_transfer($1, '2024-06-01', null, 'SDCM-0160', null, null, null) as body",
    [tesu],
  );
  const distinctions = evaluated.body.data.distinctions;
  assert.equal(distinctions.credit_recommended, true);
  assert.equal(distinctions.institution_accepts, "not_documented");
  assert.equal(distinctions.acceptance_established, false);
  assert.equal(distinctions.equivalency_documented, false);
  assert.equal(distinctions.degree_requirement_satisfied, "not_documented");
  const provenance = evaluated.body.data.recommendations[0]?.provenance[0];
  assert.match(provenance?.source_url ?? "", /acenet\.edu/);
  assert.match(provenance?.retrieved_at ?? "", /^2026-10-03/);
  assert.equal(provenance?.extraction_method, "deep_research_report");
  assert.match(provenance?.evidence_excerpt ?? "", /SDCM-0160/);

  const before = await one<{ recommended: boolean }>(
    "select api.evaluate_transfer($1, '2022-01-01', null, 'SDCM-0160', null, null, null)->'data'->'distinctions'->'credit_recommended' as recommended",
    [tesu],
  );
  const start = await one<{ recommended: boolean }>(
    "select api.evaluate_transfer($1, '2023-11-01', null, 'SDCM-0160', null, null, null)->'data'->'distinctions'->'credit_recommended' as recommended",
    [tesu],
  );
  const end = await one<{ recommended: boolean }>(
    "select api.evaluate_transfer($1, '2027-03-31', null, 'SDCM-0160', null, null, null)->'data'->'distinctions'->'credit_recommended' as recommended",
    [tesu],
  );
  const after = await one<{ recommended: boolean }>(
    "select api.evaluate_transfer($1, '2027-04-01', null, 'SDCM-0160', null, null, null)->'data'->'distinctions'->'credit_recommended' as recommended",
    [tesu],
  );
  assert.equal(before.recommended, false);
  assert.equal(start.recommended, true);
  assert.equal(end.recommended, true);
  assert.equal(after.recommended, false);

  const boundary = await one<{ accepts: string; credits: string | null }>(`
    select institution_accepts as accepts, recommended_credits::text as credits
    from api.v_recommendation_acceptance_boundary
    where authority_identifier = 'SDCM-0160'
  `);
  assert.equal(boundary.accepts, "not_derived");
  assert.equal(boundary.credits, null);
});

test("Charter Oak addresses partners without accepting them, and program requirements stay undocumented", async () => {
  const charter = await institutionId("Charter Oak State College");
  const evaluated = await one<{ accepts: string; undated: number }>(
    `select body->'data'->'distinctions'->>'institution_accepts' as accepts,
            jsonb_array_length(body->'data'->'undated_policy_context') as undated
     from (select api.evaluate_transfer($1, '2024-06-01', null, 'SDCM-0160', null, null, null) as body) q`,
    [charter],
  );
  assert.equal(evaluated.accepts, "not_documented");
  assert.equal(Number(evaluated.undated), 3);

  const links = await one<{ relationship: string }>(`
    select fp.relationship
    from policy.policy_fact_providers fp
    join alternative.providers p on p.id = fp.provider_id
    join policy.policy_facts f on f.id = fp.policy_fact_id
    join policy.policy_versions v on v.id = f.policy_version_id
    join policy.policies pol on pol.id = v.policy_id
    join catalog.institutions i on i.id = pol.institution_id
    where i.official_name = 'Charter Oak State College'
      and p.official_name = 'Study.com'
  `);
  assert.equal(links.relationship, "addresses");

  const program = await one<{ body: { data: { requirement_status: string; total_credits: number | null; practical_max_transfer_status: string; related_policy_facts: { limit_value: number | null; statement: string }[] } } }>(`
    select api.get_program_requirements(v.id) as body
    from academic.program_versions v
    join academic.programs p on p.id = v.program_id
    where v.official_program_name = 'BS Health Sciences'
  `);
  assert.equal(program.body.data.requirement_status, "not_documented");
  assert.equal(program.body.data.total_credits, null);
  assert.equal(program.body.data.practical_max_transfer_status, "not_calculated");
  const cap = program.body.data.related_policy_facts.find((fact) => Number(fact.limit_value) === 113);
  assert.ok(cap, "expected the sourced 113-credit Health Sciences fact");

  const snhu = await one<{ limit_value: string; context_value: string; unit: string }>(`
    select f.limit_value::text, f.context_value::text, f.limit_unit as unit
    from policy.policy_facts f
    join policy.policy_versions v on v.id = f.policy_version_id
    join policy.policies p on p.id = v.policy_id
    join catalog.institutions i on i.id = p.institution_id
    where i.official_name = 'Southern New Hampshire University'
      and f.fact_kind = 'transfer_maximum'
  `);
  assert.equal(snhu.unit, "credits_unspecified");
  assert.equal(Number(snhu.limit_value), 90);
  assert.equal(Number(snhu.context_value), 120);
});

test("constraints reject impossible dates, negative credits, and sourceless direct equivalencies", async () => {
  const client = await admin.connect();
  try {
    await client.query("begin");
    await assert.rejects(
      client.query(`
        insert into catalog.institution_aliases (
          institution_id, alias, normalized_alias, alias_type, valid_from, valid_to, verification_status, confidence
        )
        select id, 'Impossible', 'impossible', 'former_name', '2024-02-02', '2024-01-01', 'unreviewed', 'low'
        from catalog.institutions limit 1
      `),
      (error: { code?: string }) => error.code === "23514",
    );
    await client.query("rollback");
    await client.query("begin");
    await assert.rejects(
      client.query(`
        insert into alternative.credit_recommendations (
          learning_experience_version_id, recommendation_body_id, recommended_credits,
          recommendation_start, source_document_id, verification_status, confidence
        )
        select lev.id, rb.id, -1, '2024-01-01', cr.source_document_id, 'unreviewed', 'low'
        from alternative.learning_experience_versions lev
        join alternative.credit_recommendations cr on cr.learning_experience_version_id = lev.id
        join alternative.recommendation_bodies rb on rb.id = cr.recommendation_body_id
        limit 1
      `),
      (error: { code?: string }) => error.code === "23514",
    );
    await client.query("rollback");
    await client.query("begin");
    await assert.rejects(
      client.query(`
        insert into transfer.course_equivalencies (
          source_experience_version_id, destination_institution_id, equivalency_type,
          source_document_id, verification_status, confidence, notes
        )
        select lev.id, i.id, 'direct_course', cr.source_document_id, 'unreviewed', 'low', 'SYNTHETIC FIXTURE'
        from alternative.learning_experience_versions lev
        join alternative.credit_recommendations cr on cr.learning_experience_version_id = lev.id
        join catalog.institutions i on true
        limit 1
      `),
      (error: { code?: string }) => error.code === "23514",
    );
  } finally {
    await client.query("rollback");
    client.release();
  }
});

test("a synthetic acceptance and equivalency still do not satisfy a degree requirement", async () => {
  const client = await admin.connect();
  try {
    await client.query("begin");
    const source = await client.query("select id from provenance.source_documents limit 1");
    const sourceId = source.rows[0].id as string;
    const experience = await client.query(`
      select lev.id as version_id, le.provider_id
      from alternative.learning_experience_versions lev
      join alternative.learning_experiences le on le.id = lev.learning_experience_id
      join alternative.credit_recommendations cr on cr.learning_experience_version_id = lev.id
      where cr.authority_identifier = 'SDCM-0160'
    `);
    const versionId = experience.rows[0].version_id as string;
    const providerId = experience.rows[0].provider_id as string;
    const institution = await client.query(`
      insert into catalog.institutions (
        official_name, normalized_name, institution_type, current_status, notes
      ) values (
        'SYNTHETIC FIXTURE College', 'synthetic fixture college', 'college', 'active',
        'SYNTHETIC FIXTURE — not a researched institution'
      ) returning id
    `);
    const institutionId = institution.rows[0].id as string;

    const recommendedOnly = await client.query(
      "select api.evaluate_transfer($1, '2024-06-01', $2, null, null, null, null) as body",
      [institutionId, versionId],
    );
    assert.equal(recommendedOnly.rows[0].body.data.distinctions.credit_recommended, true);
    assert.equal(recommendedOnly.rows[0].body.data.distinctions.institution_accepts, "not_documented");
    assert.equal(recommendedOnly.rows[0].body.data.distinctions.equivalency_documented, false);
    assert.equal(recommendedOnly.rows[0].body.data.distinctions.degree_requirement_satisfied, "not_documented");

    const policy = await client.query(
      `insert into policy.policies (institution_id, policy_kind, title)
       values ($1, 'alternative_credit', 'SYNTHETIC FIXTURE provider acceptance') returning id`,
      [institutionId],
    );
    const version = await client.query(
      `insert into policy.policy_versions (
         policy_id, valid_from, from_precision, source_document_id, verification_status, confidence, notes
       ) values ($1, '2024-01-01', 'day', $2, 'unreviewed', 'low', 'SYNTHETIC FIXTURE') returning id`,
      [policy.rows[0].id, sourceId],
    );
    const fact = await client.query(
      `insert into policy.policy_facts (
         policy_version_id, fact_kind, acceptance_status, acceptance_strength,
         establishes_course_acceptance, statement, source_document_id, verification_status, confidence
       ) values (
         $1, 'acceptance_condition', 'conditional', 'provider', true,
         'SYNTHETIC FIXTURE: this college conditionally accepts the named provider.',
         $2, 'unreviewed', 'low'
       ) returning id`,
      [version.rows[0].id, sourceId],
    );
    await client.query(
      `insert into policy.policy_fact_providers (policy_fact_id, provider_id, relationship)
       values ($1, $2, 'accepts')`,
      [fact.rows[0].id, providerId],
    );

    const accepted = await client.query(
      "select api.evaluate_transfer($1, '2024-06-01', $2, null, null, null, null) as body",
      [institutionId, versionId],
    );
    assert.equal(accepted.rows[0].body.data.distinctions.institution_accepts, "conditional");
    assert.equal(accepted.rows[0].body.data.distinctions.acceptance_established, true);
    assert.equal(accepted.rows[0].body.data.distinctions.equivalency_documented, false);
    assert.equal(accepted.rows[0].body.data.distinctions.degree_requirement_satisfied, "not_documented");

    const course = await client.query(
      "insert into academic.institution_courses (institution_id) values ($1) returning id",
      [institutionId],
    );
    const courseVersion = await client.query(
      `insert into academic.course_versions (
         institution_course_id, course_code, normalized_course_code, official_title,
         source_document_id, verification_status, confidence
       ) values ($1, 'SYN 101', 'syn 101', 'SYNTHETIC FIXTURE course', $2, 'unreviewed', 'low')
       returning id`,
      [course.rows[0].id, sourceId],
    );
    await client.query(
      `insert into transfer.course_equivalencies (
         source_experience_version_id, destination_institution_id, destination_course_version_id,
         equivalency_type, valid_from, from_precision, source_document_id, verification_status, confidence, notes
       ) values ($1, $2, $3, 'direct_course', '2024-01-01', 'day', $4, 'unreviewed', 'low', 'SYNTHETIC FIXTURE')`,
      [versionId, institutionId, courseVersion.rows[0].id, sourceId],
    );

    const equated = await client.query(
      "select api.evaluate_transfer($1, '2024-06-01', $2, null, null, null, null) as body",
      [institutionId, versionId],
    );
    assert.equal(equated.rows[0].body.data.distinctions.equivalency_documented, true);
    assert.equal(equated.rows[0].body.data.distinctions.equivalency_type, "direct_course");
    assert.equal(equated.rows[0].body.data.distinctions.degree_requirement_satisfied, "not_documented");
    assert.equal(equated.rows[0].body.data.distinctions.degree_applicability.major, "not_documented");
  } finally {
    await client.query("rollback");
    client.release();
  }

  const remaining = await one<{ n: string }>("select count(*)::text as n from transfer.course_equivalencies");
  assert.equal(remaining.n, "0");
  const synthetic = await one<{ n: string }>(
    "select count(*)::text as n from catalog.institutions where official_name like 'SYNTHETIC FIXTURE%'",
  );
  assert.equal(synthetic.n, "0");
});

test("public roles can read the catalog and cannot read the research queue", async () => {
  const client = await admin.connect();
  try {
    await client.query("begin");
    await client.query("set local role edu_anon");
    const visible = await client.query("select count(*)::int as n from catalog.institutions");
    assert.equal(visible.rows[0].n, 10);
    const recommendations = await client.query("select count(*)::int as n from alternative.credit_recommendations");
    assert.equal(recommendations.rows[0].n, 1);
    await assert.rejects(
      client.query("select count(*) from provenance.research_gaps"),
      (error: { code?: string }) => error.code === "42501",
    );
    await client.query("rollback");
    await client.query("begin");
    await client.query("set local role edu_anon");
    await assert.rejects(
      client.query("select count(*) from raw.source_payloads"),
      (error: { code?: string }) => error.code === "42501",
    );
    await client.query("rollback");
    await client.query("begin");
    await client.query("set local role edu_anon");
    await assert.rejects(
      client.query("select count(*) from internal.change_log"),
      (error: { code?: string }) => error.code === "42501",
    );
    await client.query("rollback");
    await client.query("begin");
    await client.query("set local role edu_editor");
    const gaps = await client.query("select count(*)::int as n from provenance.research_gaps");
    assert.equal(gaps.rows[0].n, 35);
  } finally {
    await client.query("rollback");
    client.release();
  }
});

test("a second ingest does not duplicate canonical rows", async () => {
  const before = await one<{ n: string }>(`
    select count(*)::text as n
    from internal.change_log
    where table_name <> 'search_documents'
  `);
  const counts = await runIngest(databaseUrl, "data/raw/v1_research_extract.json");
  assert.equal(counts.institutions, 10);
  assert.equal(counts.aliases, 12);
  assert.equal(counts.identifiers, 0);
  assert.equal(counts.equivalencies, 0);
  assert.equal(counts.credit_recommendations, 1);
  assert.equal(counts.policy_facts, 16);
  assert.equal(counts.research_gaps, 35);
  const after = await one<{ n: string }>(`
    select count(*)::text as n
    from internal.change_log
    where table_name <> 'search_documents'
  `);
  assert.equal(after.n, before.n);
  const payloads = await one<{ n: string }>(
    "select count(*)::text as n from raw.source_payloads where source_family = 'v1_research_extract'",
  );
  assert.equal(payloads.n, "1");
  const still = await one<{ n: string }>("select count(*)::text as n from catalog.institutions");
  assert.equal(still.n, "10");
});

test("HTTP API enforces the same distinctions and hides the research queue", async () => {
  const app = createApp(apiPool);
  const health = await app.request("/v1/health");
  assert.equal(health.status, 200);
  const healthBody = await health.json();
  assert.equal(healthBody.ok, true);
  assert.equal(healthBody.service, "education-data-core");

  const search = await app.request("/v1/institutions?q=tesu");
  assert.equal(search.status, 200);
  const searchBody = await search.json();
  const tesuId = searchBody.data[0].id as string;
  assert.equal(searchBody.data[0].official_name, "Thomas Edison State University");

  const profile = await app.request(`/v1/institutions/${tesuId}?include_provenance=true`);
  assert.equal(profile.status, 200);
  const profileBody = await profile.json();
  assert.equal(profileBody.data.external_identifiers_status, "not_documented");
  assert.ok(profileBody.data.provenance.length > 0);
  assert.equal(profileBody.data.identifiers.length, 0);

  const missing = await app.request("/v1/institutions/00000000-0000-4000-8000-000000000000");
  assert.equal(missing.status, 404);

  const malformed = await app.request("/v1/institutions/not-a-uuid");
  assert.equal(malformed.status, 422);

  const evaluate = await app.request("/v1/transfer/evaluate", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      destination_institution_id: tesuId,
      completed_on: "2024-06-01",
      authority_identifier: "SDCM-0160",
    }),
  });
  assert.equal(evaluate.status, 200);
  const evaluateBody = await evaluate.json();
  assert.equal(evaluateBody.data.distinctions.credit_recommended, true);
  assert.equal(evaluateBody.data.distinctions.institution_accepts, "not_documented");
  assert.equal(evaluateBody.data.distinctions.equivalency_documented, false);
  assert.equal(evaluateBody.data.distinctions.degree_requirement_satisfied, "not_documented");

  const equivalencies = await app.request(`/v1/equivalencies?destination_institution_id=${tesuId}`);
  assert.equal(equivalencies.status, 200);
  const equivalencyBody = await equivalencies.json();
  assert.equal(equivalencyBody.data.length, 0);

  const gaps = await app.request("/v1/research-gaps");
  assert.equal(gaps.status, 403);

  const page = await app.request("/");
  assert.equal(page.status, 200);
  const html = await page.text();
  assert.match(html, /Education Data Core/);
  assert.match(html, /SDCM-0160/);
});
