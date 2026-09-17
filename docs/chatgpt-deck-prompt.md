# Prompt for ChatGPT: build the slide deck

Copy everything below the line into ChatGPT, and attach
`northwind-hr-on-aws.docx` in the same message.

---

You are building a slide deck for a four hour LLMOps class tonight. I am
attaching the lab handout. Read it, then produce a PowerPoint (.pptx) I can
present from, with proper AWS architecture diagrams.

## What the system is

A retrieval augmented generation system running serverless on AWS. It is an HR
assistant: employees sign in, ask questions in plain English, and get answers
from company policy documents with citations, plus the employee records they are
allowed to see.

Get these right, because they are the details most often drawn wrong:

- The chat model is **Amazon Nova Pro**, with **Amazon Nova Lite** as the
  fallback. It is **not Claude**. Do not put Claude or any Anthropic logo in any
  diagram.
- Embeddings are **Amazon Titan Text Embeddings V2**, 1024 dimensions.
- The vector store is **Amazon OpenSearch Serverless**. Not Kendra, not
  Pinecone, not a Bedrock Knowledge Base.
- The database is **Amazon Aurora PostgreSQL Serverless v2** with row-level
  security.
- Guardrails are **Amazon Bedrock Guardrails**, applied to both the question and
  the answer.
- Sign-in is **Amazon Cognito**. The API is **Amazon API Gateway (HTTP API)**
  with a JWT authorizer. The front end is a React app in **Amazon S3** behind
  **Amazon CloudFront** with **AWS WAF**.
- Everything runs in a **VPC with private subnets and no NAT gateway**. Lambda
  reaches AWS services through **VPC interface endpoints** and an **S3 gateway
  endpoint**.
- There are **four AWS Lambda functions** from one zip and one shared layer:
  chat, ingest, setup-db, evaluate. Each has its own IAM role.

## The three diagrams

Redraw each one as a real AWS architecture diagram using **official AWS
architecture icons**, in the AWS style: service icons with labels underneath,
grouped in labelled boxes for the VPC and its private subnets, arrows showing
direction of flow. Landscape, wide enough to read when projected. No cartoon
icons, no clip art, no vendor logos other than AWS.

**Diagram 1: the two flows.** Two rows on one canvas.

- **Indexing**, top row: Amazon S3 (versioned documents bucket) to AWS Lambda
  (ingest: read, chunk, embed) to Amazon Bedrock (Titan Text Embeddings V2) to
  Amazon OpenSearch Serverless. Show it is triggered by the `manifest.json`
  upload and by an Amazon EventBridge daily rule at 06:00 UTC.
- **Answering**, bottom row: Browser to Amazon Route 53 to Amazon CloudFront
  (with AWS WAF) which serves the React files from Amazon S3 and passes `/api`
  to Amazon API Gateway. API Gateway validates the Amazon Cognito token, then
  calls the chat AWS Lambda. That Lambda calls Amazon Bedrock Guardrails, Amazon
  Nova Pro on Bedrock, Amazon OpenSearch Serverless for policy search, and
  Amazon Aurora PostgreSQL for employee records.
- Draw a labelled VPC boundary around the Lambda functions, Aurora and the VPC
  endpoints. Aurora and OpenSearch must be clearly inside it, with no internet
  gateway and no NAT gateway shown.

**Diagram 2: one question, step by step.** A sequence diagram with these
participants left to right: Browser, API Gateway, Lambda (chat), Bedrock
Guardrails, Amazon Nova Pro, OpenSearch Serverless, Aurora. Use AWS icons at the
head of each lifeline. The order is:

1. Browser posts the question with the Cognito ID token
2. API Gateway validates the token, calls the chat Lambda with the email claim
3. Lambda looks up the employee in Aurora
4. Lambda checks the question with Guardrails
5. Lambda asks Nova Pro, sending the question plus two tool definitions
6. Nova Pro asks for `search_hr_policies`
7. Lambda searches OpenSearch, with the access level filter inside the query
8. Nova Pro asks for `get_employee_records`
9. Lambda reads Aurora, where row-level security decides which rows come back
10. Nova Pro returns the answer with a Sources line
11. Lambda checks the answer with Guardrails
12. Lambda writes to `request_log` and `employee_lookup_log`, and returns the
    answer with its sources

Solid arrows for calls, dashed for replies. Make it obvious that the model never
touches a database: it asks for a tool, and the Lambda decides what that tool
returns.

**Diagram 3: how an access level travels.** Two halves.

- **Indexing**: `manifest.json` supplies an `access_level` for a document. The
  document is read, chunked, embedded, and the label is attached to every chunk.
  The indexed record carries content, access_level, status and the embedding.
- **Asking**: the browser sends a question and a Cognito ID token. API Gateway
  verifies it. The chat Lambda takes the email from the token, looks up the
  person's role, maps the role to the access levels it may read, and puts those
  levels inside the OpenSearch query. Restricted documents are never candidates.

Show clearly that the access level comes from the token and the database, never
from the question.

## The deck

About 20 to 25 slides. Title slide, then follow the handout's order:

1. What we are building, with the example answers from the handout
2. From a local POC to production, using the comparison table
3. Architecture (diagram 1)
4. One question step by step (diagram 2)
5. Layers of defence, from the table in the handout
6. How a document gets its access level (diagram 3)
7. What Terraform builds, and the measured timings
8. The four Lambda functions and why there are four
9. Retrieval: the relevance floor, the gap, the keyword fallback
10. Prompt injection: direct against indirect, and the three layers
11. Guardrails, including the Test panel demo
12. What it costs, with the measured numbers
13. Watching it run: log groups, Bedrock metrics, request_log
14. The audit trail, and what INSERT-only grants buy you
15. Tear down

Use the handout's own tables where it has them. One idea per slide, short
bullets, no paragraphs.

## Numbers you may use, and no others

Every figure below was measured on a real deployment. Do not invent any others,
and do not round these differently.

| Thing | Value |
|---|---|
| `terraform apply` | 101 resources in 7 minutes 34 seconds |
| `terraform destroy` | about 20 minutes |
| Database setup | 4 seconds |
| Indexing | 50 documents into 328 chunks in 78 seconds |
| A warm question | 3 to 5 seconds |
| A blocked prompt injection | 0 input tokens, 176 ms |
| Nova Pro price | $0.80 per million input tokens, $3.20 per million output |
| Titan embeddings price | $0.01 per million tokens |
| Whole lab's model usage | about $0.14 |
| Evaluation set | 17 cases |
| Corpus | 50 documents, 47 current and 3 superseded |
| Employees | 12, of whom 4 have a Cognito login |

## Style

- Plain English. Short sentences. No sentence longer than about 20 words.
- **No em dashes anywhere.** Use a comma, a colon or a full stop.
- Do not invent claims about what most teams or most companies do.
- Do not add statistics, benchmarks or quotes that are not in the handout.
- Do not use the word "interview".
- If something in the handout is unclear, leave it out rather than guessing.

Produce the .pptx as a downloadable file, and list anything you left out.
