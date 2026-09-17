# Running a RAG system: the LLMOps notes

The lab gets the system deployed. This is the part the job is actually about.
Knowing what it costs. Seeing what it is doing. Proving it still works after a
change, and being able to say who saw what.

It is written as two halves, because that is how these systems break, and how
people end up talking about them. **Indexing** is everything that happens before a
question is asked. **Retrieval** is everything that happens after.

Every number marked *measured* came from this project running in a real AWS
account. Prices came from the AWS Pricing API on 2026-09-17 and will drift.

---

## Part 1: Indexing

Everything here runs on a schedule or on an upload. Nobody is waiting, so you
can afford to be slow and careful. Get it wrong and no amount of clever
retrieval saves you.

### Where does the data come from?

| Ask | Why it matters |
|---|---|
| Who owns these documents, and who decides what is published? | You need a human owner for "which of these two is current" |
| Where do they live now: SharePoint, Confluence, Drive, a file share, a CMS? | That decides your connector and your auth, which is usually more work than the RAG |
| How do you find out a document changed? | Polling, a webhook, or a nightly full rebuild. All three are valid, they fail differently |
| What is the deletion story? | If a document is withdrawn, how long until it stops being answerable? |
| Is any of it restricted? | If yes, permissions must be part of the pipeline from day one, not added later |

**In this project.** S3 is the source of truth, `manifest.json` is the index of
record, and an upload of the manifest triggers a full rebuild. There is also a
daily EventBridge rebuild as a safety net. That is deliberately the simplest
thing that works: a full rebuild of 50 documents takes 78 seconds *(measured)*,
so incremental indexing would be complexity with no payoff. At a hundred
thousand documents it is the opposite.

**Full rebuild or incremental?** It depends on two numbers: how long a full
rebuild takes, and how stale the index is allowed to get. Below a few minutes,
full rebuilds win. They are simpler and they cannot drift out of step with the
source.

### Loading and parsing

Budget more time for this than feels reasonable.

| Format | What goes wrong |
|---|---|
| PDF | Text-layer PDFs are fine. Scans are images and need OCR. Two-column layouts read across the columns unless the parser understands them |
| DOCX | Tables and headers are easy to lose. Tracked changes may still be in there |
| HTML | Navigation, cookie banners and footers become chunks that match everything |
| CSV / XLSX | A row is a fact. Chunk the file as prose and the fact disappears |
| PowerPoint | Speaker notes are often the real content |

**Popular choices, and what people reach for:**

- **Unstructured.io** is the usual default for mixed corpora. It handles many
  formats and returns typed elements.
- **LlamaParse** and similar hosted parsers do better on complex PDFs and
  tables, at a per-page cost.
- **PyMuPDF / pypdf** for text-layer PDFs when you want no dependencies.
- **Amazon Textract** for anything scanned, or where you need tables and forms
  out of an image. It is a separate pipeline stage with its own cost and latency,
  not a checkbox.
- **Docling**, **Apache Tika** for broad format coverage in a JVM stack.

**In this project.** `documents.py` has six small readers and no framework. The
CSV reader returns **one section per row**, which is the only reason "is
Juneteenth a holiday" is answerable at all. That single decision matters more
than the embedding model.

**Tables need deciding, not parsing.** A row is usually one fact, so a row
should usually become one chunk. "The parser handles it" is not a plan. Prove it
with a question that can only be answered from a single row.

### Chunking

| Ask | Practical answer |
|---|---|
| How big? | Big enough to hold a whole answer, small enough not to dilute the match. 500 to 1000 tokens is the common range |
| Overlap? | Enough that a sentence split across a boundary still appears whole somewhere. 10 to 15 percent is typical |
| Split on what? | Headings first, then size. Splitting purely on character count cuts sentences in half |
| Does the chunk know where it came from? | It must. Title, section and document id travel with the text, or you cannot cite |

**In this project.** 700 characters with 80 overlap, split on headings first, and
each chunk carries `title`, `section`, `filename`, `access_level` and `status`.

**A chunk size quoted without reference to your documents is a guess.** Measure
it with an evaluation set, the same way you measure the relevance floor.

### Embedding

| Ask | Why it matters |
|---|---|
| Which model, and what dimension? | Storage and latency scale with dimension. More is not free |
| Same model for documents and questions? | It must be. Different models produce incompatible vectors |
| What happens when you change it? | You rebuild the entire index. That is a migration with a cost and a window |
| Is the data allowed to leave your account? | Decides self-hosted versus API |

**Popular choices:**

| Model | Dimensions | Note |
|---|---|---|
| Amazon Titan Text Embeddings V2 | 1024, 512 or 256 | What this project uses. On Bedrock, IAM auth, no key |
| Cohere Embed 3 | 1024 | Strong multilingual, also on Bedrock |
| OpenAI text-embedding-3-small / large | 1536 / 3072 | Very widely used outside AWS |
| BGE / E5 / GTE (open weights) | 384 to 1024 | Self-hosted, free per call, you run the GPU. The POC used bge-small at 384 |

**In this project.** Titan V2 at 1024 dimensions, normalised, so inner product
gives the same ranking as cosine with less arithmetic.

**Embedding is not where the money goes.** *Measured here:* embedding the whole
corpus and every query across the entire lab came to **$0.00088**. The chat model
cost about 160 times more.

### The vector store

| Ask | Why it matters |
|---|---|
| Does it filter *inside* the search? | If it filters afterwards you cannot do access control properly |
| What does it cost when idle? | Many vector stores bill for existing, not for use |
| Does it do hybrid search? | Vector plus keyword, fused. Matters for codes and acronyms |
| How do you rebuild without downtime? | Build a new index, then swap an alias |

**Popular choices:**

| Store | Typically chosen when |
|---|---|
| OpenSearch / Elasticsearch | You want hybrid search and already run it. This project |
| pgvector in PostgreSQL | You already have Postgres and do not want another system. The POC |
| Pinecone | Managed, no ops, per-hour pods |
| Qdrant, Weaviate, Milvus | Open source, self-hosted or cloud |
| FAISS | In-process, no server. Great for a prototype, no filtering story |

**pgvector is genuinely fine up to a few million vectors.** The reasons to
leave it are hybrid search, sharding, and not wanting search traffic on your
transactional database. "We need a real vector database" is not one of them on
its own.

---

## Part 2: Retrieval

Now someone is waiting. Everything here is on a latency budget, and in this
project that budget is **29 seconds**, because API Gateway gives up at 30.

### The questions to ask

| Ask | What goes wrong |
|---|---|
| Can it say "I don't know"? | Vector search always returns its closest match, even for "hello". Without a floor it will answer anyway |
| Does everyone see the same corpus? | If not, the filter must run *inside* the query, not over the results |
| How do you handle codes and acronyms? | "L5", "PTO", "NW-POL-010" are nearly invisible to an embedding model. That is what keyword search is for |
| What happens on a follow-up question? | The model has no memory. Either resend the history or resolve references before searching |
| Where do citations come from? | The retrieved chunk, never the model's memory |

**In this project.** A relevance floor of 0.25, a gap of 0.10 from the best
match, a keyword fallback when the vectors find nothing convincing, and the
access filter inside the kNN query. All four are in `retrieval.py` and
`search_index.py` and are worth reading together.

### Choosing the chat model

**Popular choices on Bedrock**, from the live catalogue in us-east-1: the Nova
family, Claude, Llama, Mistral, DeepSeek, Qwen, Gemma and the GPT-OSS models.
Roughly seventy have on-demand pricing.

What actually decides it:

| Ask | Why it matters |
|---|---|
| Can you call it *today*, in your account and region? | Anthropic models need a one-time use case form. That is a schedule risk, not a technical one |
| Does it support tool use? | This whole design depends on it |
| What is the fallback, and is it from a different family? | Two models from the same vendor tend to be unavailable together |
| Does the fallback fit inside your timeout? | *Measured here:* the SDK spent 15 of 29 seconds retrying before the fallback even started |
| Does data have to stay in one geography? | Use a regional inference profile (`us.`, `eu.`) rather than `global.` |

**In this project.** Nova Pro with Nova Lite as the fallback, both reached
through the Converse API so the model is a Terraform variable. We tested Lite as
the primary: it called the wrong tool and invented a citation, so it is good
enough to degrade to and not good enough to lead with.

### Putting it in Slack or Teams

It is wiring, not AI work.

The React app is one client of the API. Slack or Teams would be another. The
retrieval, the access filter, the row-level security, the prompt and the model do
not change, because they sit behind the API and never knew which client was
calling.

What you write is an adapter: receive the webhook, verify its signature, map the
sender to an employee, call `POST /api/chat`, format the reply. Ordinary
application code.

The part that needs care is the identity mapping. API Gateway trusts a Cognito
token; a Slack event gives you a Slack user id. Mapping one to the other has to
go through something verified, normally the email on the SSO account behind both.
Match on a display name or a handle and you have put a spoofable field in front
of salary data.

---

## Part 3: What it costs, measured

Prices from the AWS Pricing API, us-east-1, 2026-09-17:

| Model | $ per 1M input | $ per 1M output |
|---|---|---|
| Nova Pro | $0.80 | $3.20 |
| Nova Lite | $0.06 | $0.24 |
| Nova Micro | $0.03 | $0.14 |
| Titan Text Embeddings V2 | $0.01 | n/a |

Actual usage for this project, read from CloudWatch:

| Model | Invocations | Input tokens | Output tokens | Cost |
|---|---|---|---|---|
| Nova Pro | 156 | 144,232 | 7,593 | $0.1397 |
| Nova Lite | 9 | 5,388 | 395 | $0.0004 |
| Titan Embeddings V2 | 1,254 | 87,862 | n/a | $0.0009 |
| **Total** | | | | **about $0.14** |

**The whole lab's model usage cost fourteen cents.** Per Bedrock call that is
**$0.0009**. A single question is two or three calls because of the tool loop,
so call it a fifth of a cent per question.

Three things follow from that:

1. **Input tokens dominate.** 144,232 in against 7,593 out. RAG stuffs retrieved
   text into every prompt, so the corpus you send is the bill. Sending 8 chunks
   instead of 4 doubles your cost and often does not improve the answer.
2. **The model is not what costs money here.** At this volume, OpenSearch
   Serverless at roughly $7 a day dwarfs fourteen cents of inference. The
   infrastructure that exists whether or not anyone asks a question is the bill.
3. **Nova Pro is 13x the price of Nova Lite.** That is the real fallback
   tradeoff, and the reason to check whether the cheap model is good enough for
   your actual questions rather than assuming.

### Working out cost per call yourself

```sql
SELECT
  count(*)                                  AS questions,
  sum(input_tokens)                         AS in_tokens,
  sum(output_tokens)                        AS out_tokens,
  round(sum(input_tokens)  * 0.80 / 1e6
      + sum(output_tokens) * 3.20 / 1e6, 4) AS usd
FROM request_log;
```

The rates are hard-coded there on purpose. If the model changes, that number is
wrong until someone updates it, which is the kind of thing worth a comment and a
calendar reminder.

---

## Part 4: What you can actually see

### Bedrock publishes per-model metrics to CloudWatch

Namespace `AWS/Bedrock`, dimensioned by `ModelId`. Nothing to enable:

```bash
aws cloudwatch list-metrics --namespace AWS/Bedrock \
  --query 'Metrics[].[MetricName,Dimensions[0].Value]' --output text | sort -u
```

You get `Invocations`, `InputTokenCount`, `OutputTokenCount`,
`InvocationLatency`, `InvocationClientErrors`, `InvocationServerErrors`,
`InvocationThrottles` and `EstimatedTPMQuotaUsage`, per model.

**A nice thing to show.** In this account, the Claude model we could not get
access to still appears, with `Invocations: 2` and
`InvocationClientErrors: 2` and no tokens at all. The two failed access attempts
are permanently visible, months later, and cost nothing. That is what a
client-side rejection looks like in metrics.

*Measured average latency:* Nova Pro 652 ms, Nova Lite 502 ms, Titan 105 ms.
Those are the model's own time, not your end-to-end 3 to 5 seconds, and the
difference between them is your code, your database and your search.

### What CloudWatch cannot tell you

It does not know which tools ran, which retrieval path answered, who asked, or
whether the answer was any good. It reports per model, not per question, so you
cannot attribute a spike to a user or a feature.

That is why the application writes `request_log`: one row per question with the
question, the tools used, both token counts and the latency. **Platform metrics
come free. Product metrics you write yourself**, and for an LLM application the
product metrics are the ones with money attached.

### Bedrock model invocation logging

Off by default. You can turn it on to have Bedrock write the full prompt and
completion to S3 or CloudWatch Logs. This project does not enable it. The prompts
contain HR policy text and employee salary data, so turning it on creates a
second copy of that data in a place with different access controls. If you enable it, that bucket needs the
same care as the database.

---

## Part 5: The audit trail

Yes. Four tables, holding different things:

| Table | What it holds | Who can read it |
|---|---|---|
| `conversations` | one row per chat | the app, that employee's own rows |
| `messages` | every question and answer, with the sources cited | the app, that employee's own rows |
| `request_log` | per question: tools used, input and output tokens, latency | **nobody through the app** |
| `employee_lookup_log` | who looked at employee records, and which ids came back | **nobody through the app** |

The last two are the audit trail proper, and the interesting part is in
`02_security.sql`:

```sql
GRANT INSERT ON request_log, employee_lookup_log TO hr_app;
```

`INSERT` only. The application writes both logs and **cannot read, update or
delete either**. Reading them needs the admin credentials, which the application
never has. A component that writes an audit trail should not be able to edit it,
and here that is enforced by Postgres rather than promised in a code review.

Try it: query `request_log` with the app user and you get
`permission denied for table request_log`.

**What is missing, and worth saying so.** There is no retention policy on either
log, no export to anywhere durable, and no alert on unusual access patterns. A
real deployment would need all three, plus a decision about how long you keep
questions that contain personal information.

**Proving who saw a salary** means `employee_lookup_log`, joined to `messages`
by time. What makes it evidence rather than a log file is that the application
had no permission to change it.

---

## Part 6: What belongs in the pipeline

The evaluation set is a gate, not something you run when you remember.

### Run on every change

| Change | What to run |
|---|---|
| Any code change | Unit tests, then the full evaluation |
| A prompt change | The full evaluation. Prompts are code and deserve review |
| A model change | The full evaluation, plus check latency against your timeout |
| A chunking or embedding change | Rebuild the index first, then the full evaluation |
| A threshold change | The similarity report, then the full evaluation |
| A document added or retired | The evaluation cases that touch it, and the duplicate-title check |

### What a reasonable pipeline does

```
lint + unit tests          fast, no AWS
  -> terraform validate + plan     catches drift and syntax
  -> deploy to a test stack
  -> setup-db + load documents
  -> run the evaluation            <- the gate
  -> compare against the last run  <- the other gate
  -> promote, or stop
```

Two gates, not one. The first is an absolute floor: fail if the pass count drops
below an agreed number. The second is a comparison: fail if **any case that
passed yesterday fails today**, even if the total went up. A score that stays at
12 while two cases swap places is a regression hiding inside a stable number.

This is also why `TEMPERATURE = 0.0` is set in `assistant.py`. A test that gives
a different answer each run cannot gate anything.

### Things worth adding beyond pass or fail

| Check | Why |
|---|---|
| Latency budget | Fail if p90 goes above your timeout minus a margin |
| Cost per question | Fail if it jumps. A prompt edit that adds two chunks is a permanent bill increase |
| Refusal cases | The system must still refuse. A model that got more helpful may have got more leaky |
| Citation validity | Every cited document should exist and be one the asker may read |
| Guardrail probes | A known prompt injection should still be blocked at 0 tokens |
| Index sanity | Chunk count within a few percent of the last run. A silent drop means a parser broke |

The last one catches the failure mode nothing else does: ingestion "succeeds",
produces 40 percent fewer chunks, and every answer quietly gets worse.

### Not built here, and worth being honest about it

This project has no pipeline. The evaluation runs when you invoke it, and three
of the four test files cannot run outside the VPC. Building that pipeline is the
natural next piece of work, and the two realistic shapes are an SSM bastion or a
test-runner Lambda in the same subnets.

That is the honest next piece of work on this system.
