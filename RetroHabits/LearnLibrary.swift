import Foundation

/// The card deck for the LEARN feed — a curated crash course in AI engineering.
/// Everything ships in the app, so the feed works offline.
enum LearnLibrary {

    static let all: [LearnCard] = llm + rag + cloud + nlp

    // MARK: - LLMs

    static let llm: [LearnCard] = [
        LearnCard(
            id: "llm-tokens",
            track: .llm,
            visual: .tokens,
            title: "TOKENS",
            hook: "Models don't read words. They read tokens.",
            body: """
            Before a model sees your text, a tokenizer chops it into pieces called tokens — roughly 4 characters or ¾ of a word in English. "Unbelievable" might become "un", "bel", "iev", "able".

            This is why models are weird about spelling and counting letters: they never saw the letters, only the chunks. It's also why token counts drive your bill — you pay per token in and per token out.

            Rule of thumb: 1,000 tokens ≈ 750 English words. Code and non-English text use more tokens per character, so they cost more.
            """,
            terms: ["Tokenizer", "BPE", "Token limit", "Cost per 1M tokens"],
            action: "Paste a paragraph into a tokenizer visualizer and watch where the splits land."
        ),
        LearnCard(
            id: "llm-attention",
            track: .llm,
            visual: .attention,
            title: "ATTENTION",
            hook: "The idea that made all of this possible.",
            body: """
            Attention lets every token look at every other token and decide which ones matter. Processing "it" in "the trophy didn't fit in the suitcase because it was too big", attention learns to weight "trophy" heavily — that's how the model resolves what "it" refers to.

            Mechanically each token emits a query, a key, and a value. Queries are matched against keys to produce weights; the output is the weighted sum of values. Multi-head attention runs many of these in parallel, each learning a different relationship.

            The catch: comparing every token to every other is O(n²). Doubling your context roughly quadruples the compute. That single fact drives most of the research on long-context models.
            """,
            terms: ["Query/Key/Value", "Multi-head", "Self-attention", "O(n²)"],
            action: "Read \"The Illustrated Transformer\" by Jay Alammar — still the clearest explainer."
        ),
        LearnCard(
            id: "llm-transformer",
            track: .llm,
            visual: .stack,
            title: "THE TRANSFORMER",
            hook: "Attention Is All You Need, 2017.",
            body: """
            A transformer is a stack of identical blocks. Each block does two things: attention (tokens exchange information) and a feed-forward network (each token gets processed independently). Residual connections and layer norm keep the gradients sane as you stack dozens of these.

            The original paper had an encoder and a decoder for translation. Modern chat models are decoder-only: they just predict the next token, over and over, feeding each prediction back in.

            That's the whole trick. Everything from GPT to Claude to Llama is this architecture scaled up with better data and training.
            """,
            terms: ["Decoder-only", "Residual connection", "Layer norm", "Feed-forward"],
            action: "Watch Karpathy's \"Let's build GPT\" and type it out yourself. Two hours, enormous payoff."
        ),
        LearnCard(
            id: "llm-pretrain",
            track: .llm,
            visual: .pipeline,
            title: "PRETRAIN → POST-TRAIN",
            hook: "Two very different phases with very different budgets.",
            body: """
            Pretraining: predict the next token across a huge chunk of the internet. Costs millions of dollars, produces a model with vast knowledge and no manners — it will happily continue your text rather than answer you.

            Post-training turns it into an assistant. Supervised fine-tuning on example conversations teaches the format; then preference tuning (RLHF, DPO, and friends) teaches it which of two answers a human prefers.

            As an AI engineer you'll almost never pretrain. You'll fine-tune, prompt, or retrieve — and knowing which of those three to reach for is most of the job.
            """,
            terms: ["Pretraining", "SFT", "RLHF", "DPO", "Base vs instruct model"],
            action: "Compare a base model and its instruct version on the same prompt. The difference is stark."
        ),
        LearnCard(
            id: "llm-context",
            track: .llm,
            visual: .pipeline,
            title: "CONTEXT WINDOW",
            hook: "The model's entire working memory.",
            body: """
            Everything the model knows in the moment — system prompt, your history, retrieved documents, tool outputs — lives in one buffer. Nothing else persists. Each turn you resend the whole conversation; the model has no memory between calls.

            Bigger windows aren't free. Cost and latency scale with what you send, and models get measurably worse at using information buried in the middle of a long context — the "lost in the middle" effect.

            So context is a budget to manage, not a container to fill. Put the important things at the start or the end.
            """,
            terms: ["Context window", "Lost in the middle", "KV cache", "Prompt caching"],
            action: "Take your longest prompt and cut it 50%. Measure whether quality actually dropped."
        ),
        LearnCard(
            id: "llm-sampling",
            track: .llm,
            visual: .curve,
            title: "TEMPERATURE",
            hook: "The model outputs a probability distribution, not an answer.",
            body: """
            At each step the model produces a probability for every token in its vocabulary. Sampling picks one. Temperature reshapes that distribution: near 0 it always takes the most likely token (deterministic, repetitive); higher values flatten the curve and let unlikely tokens through (creative, riskier).

            Top-p (nucleus sampling) is the other common dial: keep only the smallest set of tokens whose probabilities add to p, then sample from those.

            Practical defaults: temperature 0 for extraction, classification, and anything you'll parse. 0.7–1.0 for writing and brainstorming.
            """,
            terms: ["Logits", "Softmax", "Temperature", "Top-p", "Greedy decoding"],
            action: "Run the same prompt at temperature 0 and 1.2, five times each. Watch the variance."
        ),
        LearnCard(
            id: "llm-hallucination",
            track: .llm,
            visual: .network,
            title: "HALLUCINATION",
            hook: "It's not lying. It's predicting.",
            body: """
            A model trained to produce plausible text will produce plausible text even when it doesn't know. There's no internal flag for "I'm making this up" — a confident wrong citation and a confident right one are generated by the same process.

            The three real mitigations: ground it (RAG, so answers cite retrieved sources), constrain it (structured output, tool calls, validation), and verify it (a second pass that checks claims against sources).

            "Just tell it not to hallucinate" is not a mitigation. Neither is a bigger model — it hallucinates less, not never.
            """,
            terms: ["Grounding", "Citation", "Faithfulness", "Confabulation"],
            action: "Ask a model for five papers on a niche topic, then check every DOI. Sobering."
        ),
        LearnCard(
            id: "llm-scaling",
            track: .llm,
            visual: .curve,
            title: "SCALING LAWS",
            hook: "Loss falls predictably with compute, data, and parameters.",
            body: """
            Model performance follows smooth power laws: throw 10× the compute at it and the loss drops by a predictable amount. This is why the field kept building bigger — the curve kept holding.

            Chinchilla (2022) corrected an early mistake: most models were too big for their data. For a fixed compute budget you want roughly 20 training tokens per parameter. That's why a well-trained 8B model can beat a badly-trained 70B one.

            Newer work shifts spend to inference — letting a model think longer at answer time instead of only training it bigger.
            """,
            terms: ["Power law", "Chinchilla-optimal", "Compute budget", "Test-time compute"],
            action: "Skim the Chinchilla paper's abstract and figure 1. That's 90% of the insight."
        ),
        LearnCard(
            id: "llm-finetune",
            track: .llm,
            visual: .stack,
            title: "LORA & PEFT",
            hook: "Fine-tune a 70B model on one GPU.",
            body: """
            Full fine-tuning updates every weight — for a big model that means enormous memory. LoRA freezes the original weights and trains two small low-rank matrices alongside them. You end up training well under 1% of the parameters and shipping adapter files of a few megabytes.

            QLoRA goes further: quantize the frozen base to 4-bit, then LoRA on top. That's what puts large-model fine-tuning on consumer hardware.

            When to fine-tune at all: you need a specific format, tone, or narrow skill. When NOT to: you need the model to know new facts — that's a retrieval problem, not a training one.
            """,
            terms: ["LoRA", "QLoRA", "Rank", "Adapter", "PEFT"],
            action: "Fine-tune a small model on 100 of your own examples with Unsloth or Axolotl."
        ),
        LearnCard(
            id: "llm-quantization",
            track: .llm,
            visual: .stack,
            title: "QUANTIZATION",
            hook: "Same model, a quarter of the memory.",
            body: """
            Weights are usually 16-bit floats. Quantization stores them in 8 or 4 bits instead. A 7B model drops from ~14GB to ~4GB — suddenly it runs on a laptop.

            Quality loss at 8-bit is nearly invisible; at 4-bit it's small but real, and formats like GPTQ, AWQ and GGUF differ in how cleverly they pick which precision goes where.

            The tradeoff is memory and speed against accuracy. For most applications 4-bit is fine, and it's the difference between shipping and not.
            """,
            terms: ["FP16", "INT8", "GGUF", "AWQ", "Perplexity delta"],
            action: "Run a 4-bit model locally with Ollama or LM Studio and compare it to the API version."
        ),
        LearnCard(
            id: "llm-moe",
            track: .llm,
            visual: .network,
            title: "MIXTURE OF EXPERTS",
            hook: "A trillion parameters, but you only pay for a few billion.",
            body: """
            In an MoE model the feed-forward layer is split into many "experts", and a small router picks two or three per token. Total parameters are huge; active parameters per token are small.

            You get the knowledge capacity of a giant model at the inference cost of a much smaller one. The trade is memory — all experts must be loaded even though most sit idle each step.

            Most frontier models are believed to use some version of this. It's the main reason capability keeps rising while per-token prices keep falling.
            """,
            terms: ["Router", "Active vs total params", "Sparse MoE", "Expert"],
            action: "Compare Mixtral's active parameter count to its total. The gap explains the pricing."
        ),
        LearnCard(
            id: "llm-evals",
            track: .llm,
            visual: .pipeline,
            title: "EVALS",
            hook: "The skill that separates hobbyists from engineers.",
            body: """
            Vibes don't scale. The moment you have a prompt in production you need a dataset of inputs and a way to score outputs, so that "I improved it" becomes a number instead of a feeling.

            Three scoring approaches: exact/programmatic checks (best — did the JSON parse, is the number right), model-as-judge (flexible, needs its own validation), and human review (gold standard, expensive, use it to calibrate the other two).

            Start with 20 hand-picked hard cases. That tiny set will catch more regressions than any public benchmark.
            """,
            terms: ["Golden dataset", "LLM-as-judge", "Regression suite", "Pass@k"],
            action: "Write 20 test cases for something you've built, and run them before every prompt change."
        ),
        LearnCard(
            id: "llm-agents",
            track: .llm,
            visual: .network,
            title: "TOOLS & AGENTS",
            hook: "A model that can act, not just answer.",
            body: """
            Tool use is simple in principle: you describe functions in the request, the model responds with a structured call instead of prose, your code runs it and feeds the result back. Loop until done.

            An "agent" is that loop plus autonomy over how many steps to take. Power comes with failure modes: loops that never terminate, compounding errors across steps, and cost that scales with iterations.

            Production agents need step limits, timeouts, and a way for a human to interrupt. Build the guardrails before you build the ambition.
            """,
            terms: ["Function calling", "ReAct", "Tool schema", "Step limit", "Agent loop"],
            action: "Build a two-tool agent (search + calculator) and log every step it takes."
        )
    ]

    // MARK: - RAG

    static let rag: [LearnCard] = [
        LearnCard(
            id: "rag-what",
            track: .rag,
            visual: .pipeline,
            title: "WHAT IS RAG?",
            hook: "Open-book exam instead of memory test.",
            body: """
            Retrieval-Augmented Generation: before answering, fetch relevant documents and paste them into the prompt. The model answers from what's in front of it rather than from what it memorized.

            This fixes the three big problems at once — stale knowledge (your docs update, no retraining), private data (the model never trained on your company wiki), and hallucination (answers can cite sources).

            The pipeline is always the same five steps: chunk your documents, embed them, store the vectors, retrieve the top matches for a query, stuff them into the prompt.
            """,
            terms: ["Retrieval", "Grounding", "Chunk", "Top-k", "Citation"],
            action: "Build a RAG over your own class notes. It's the single best learning project in AI engineering."
        ),
        LearnCard(
            id: "rag-embeddings",
            track: .rag,
            visual: .vectors,
            title: "EMBEDDINGS",
            hook: "Meaning, as coordinates.",
            body: """
            An embedding model turns text into a list of numbers — typically 384 to 3,072 of them — positioned so that similar meanings land near each other. "Dog" sits near "puppy" and far from "quarterly earnings".

            Because meaning becomes geometry, search becomes math. You embed the query, then find the document vectors closest to it, usually by cosine similarity.

            Critical rule: query and documents must be embedded by the same model. Mixing embedding models produces garbage silently — no error, just bad results.
            """,
            terms: ["Vector", "Cosine similarity", "Dimension", "Semantic search"],
            action: "Embed 20 sentences, compute the similarity matrix, and see what clusters."
        ),
        LearnCard(
            id: "rag-chunking",
            track: .rag,
            visual: .tokens,
            title: "CHUNKING",
            hook: "The most underrated variable in your whole pipeline.",
            body: """
            You can't embed a 300-page PDF as one vector — meaning gets averaged into mush. So you split it. How you split determines what's retrievable.

            Too small and chunks lose the context that makes them make sense. Too large and one chunk contains five topics, so its vector is vague and matches nothing well. 200–500 tokens with 10–20% overlap is a reasonable starting point.

            Better than any fixed size: split on structure. Headings, sections, paragraphs. A chunk that maps to one idea retrieves far better than one that maps to one arbitrary token count.
            """,
            terms: ["Chunk size", "Overlap", "Semantic chunking", "Parent-child retrieval"],
            action: "Take one bad RAG answer and look at the chunks it retrieved. Usually the bug is right there."
        ),
        LearnCard(
            id: "rag-vectordb",
            track: .rag,
            visual: .cluster,
            title: "VECTOR DATABASES",
            hook: "Nearest-neighbour search at scale.",
            body: """
            Comparing a query against every vector is exact but slow past a few hundred thousand documents. Vector databases use approximate nearest neighbour indexes — HNSW being the common one — to find near-matches in milliseconds by only searching a fraction of the space.

            "Approximate" means you trade a little recall for a lot of speed, tuned by parameters like ef_search.

            Options run from pgvector (Postgres you already have) to Qdrant, Weaviate and Pinecone. Honest advice: start with pgvector. Most projects never outgrow it, and one less service is a real feature.
            """,
            terms: ["ANN", "HNSW", "Recall", "pgvector", "Index"],
            action: "Load 10k vectors into pgvector and compare exact vs approximate search times."
        ),
        LearnCard(
            id: "rag-hybrid",
            track: .rag,
            visual: .pipeline,
            title: "HYBRID SEARCH",
            hook: "Semantic search alone will miss the obvious.",
            body: """
            Embeddings understand meaning but fumble exact strings — error codes, product SKUs, surnames, "section 4.2.1". Keyword search (BM25) nails those and misses paraphrases.

            Hybrid runs both and fuses the rankings, usually with Reciprocal Rank Fusion. It's a small amount of extra code for one of the largest quality jumps available in RAG.

            If your retrieval is disappointing and you're pure-vector, this is the first thing to try.
            """,
            terms: ["BM25", "RRF", "Sparse vs dense", "Fusion"],
            action: "Search your index for an exact ID with vectors only, then with hybrid. Note the difference."
        ),
        LearnCard(
            id: "rag-rerank",
            track: .rag,
            visual: .stack,
            title: "RERANKING",
            hook: "Retrieve 50, keep the best 5.",
            body: """
            Retrieval optimizes for speed, so it's approximate. A reranker (cross-encoder) reads the query and each candidate together and scores true relevance — far more accurate, far too slow to run over your whole corpus.

            So you stage it: fast retrieval casts a wide net, the reranker sorts what came back, and only the top few reach the prompt.

            This also saves money. Five great chunks beat twenty mediocre ones on both quality and token cost.
            """,
            terms: ["Cross-encoder", "Bi-encoder", "Two-stage retrieval", "Cohere Rerank"],
            action: "Add a reranker over your top-50 and measure whether the right chunk moves into the top-3."
        ),
        LearnCard(
            id: "rag-queries",
            track: .rag,
            visual: .network,
            title: "QUERY REWRITING",
            hook: "The user's question is rarely the best search query.",
            body: """
            People ask "what about the second one?" — meaningless to a search index without the conversation. Or they ask something broad that needs three separate lookups.

            Fixes: rewrite follow-ups into standalone questions using chat history; decompose complex questions into sub-queries and retrieve for each; or generate a hypothetical ideal answer and embed that instead (HyDE), since answers look more like documents than questions do.

            All of these cost one extra small model call and routinely beat weeks of embedding tuning.
            """,
            terms: ["Query expansion", "HyDE", "Decomposition", "Standalone question"],
            action: "Log the queries your RAG actually searches with. The gap from user intent is eye-opening."
        ),
        LearnCard(
            id: "rag-failures",
            track: .rag,
            visual: .pipeline,
            title: "WHY RAG FAILS",
            hook: "Debug it in order, not at random.",
            body: """
            Failures land in one of three buckets, and knowing which saves days.

            Retrieval failure: the right chunk was never returned. Look at chunking, embeddings, hybrid search, reranking. Generation failure: the right chunk was returned and the model ignored it or misread it. Look at your prompt and how you formatted the context. Data failure: the answer isn't in your corpus at all — no pipeline can fix that.

            Always inspect the retrieved chunks before touching the prompt. Most teams tune prompts to fix retrieval bugs and get nowhere.
            """,
            terms: ["Context precision", "Context recall", "Faithfulness", "Answer relevance"],
            action: "Print the retrieved chunks alongside every answer during development. Non-negotiable."
        ),
        LearnCard(
            id: "rag-eval",
            track: .rag,
            visual: .curve,
            title: "EVALUATING RAG",
            hook: "Two systems, two sets of metrics.",
            body: """
            Score retrieval and generation separately or you'll never know which is broken.

            Retrieval: context recall (did we fetch what was needed?) and context precision (was the good stuff ranked high?). Generation: faithfulness (is every claim supported by the retrieved text?) and answer relevance (did it address the question?).

            Frameworks like RAGAS compute these for you. Even better: build 30 question/answer pairs from your own corpus by hand — that set will teach you more than any generic benchmark.
            """,
            terms: ["RAGAS", "Context recall", "Faithfulness", "Ground truth"],
            action: "Hand-write 30 Q&A pairs from your documents and score your pipeline against them."
        ),
        LearnCard(
            id: "rag-graph",
            track: .rag,
            visual: .network,
            title: "BEYOND PLAIN RAG",
            hook: "When top-k chunks aren't enough.",
            body: """
            Some questions can't be answered by any five chunks — "what themes recur across all 400 support tickets?" needs the whole corpus, not a sample.

            GraphRAG builds an entity-and-relationship graph from your documents and traverses it, which handles multi-hop questions ("who reported to the person who wrote this policy?"). Hierarchical summarization pre-computes summaries at several levels so broad questions hit a summary instead of raw chunks.

            Both cost real preprocessing. Use them when you've proven plain RAG can't answer the questions your users actually ask.
            """,
            terms: ["GraphRAG", "Multi-hop", "Knowledge graph", "Hierarchical summary"],
            action: "Write down three questions plain RAG fails on. That list justifies the next architecture."
        )
    ]

    // MARK: - Cloud

    static let cloud: [LearnCard] = [
        LearnCard(
            id: "cloud-serving",
            track: .cloud,
            visual: .pipeline,
            title: "SERVING MODELS",
            hook: "Training is a project. Serving is a system.",
            body: """
            Inference has two phases with different bottlenecks. Prefill processes your whole prompt at once — compute-bound, parallel, fast. Decode generates one token at a time, each depending on the last — memory-bandwidth-bound and stubbornly sequential.

            That's why time-to-first-token and tokens-per-second are separate metrics, and why a long prompt with a short answer behaves completely differently from the reverse.

            Serving stacks like vLLM and TGI exist to squeeze this: continuous batching, paged attention, speculative decoding.
            """,
            terms: ["Prefill", "Decode", "TTFT", "Throughput", "vLLM"],
            action: "Measure TTFT and total time separately in your app. They tell different stories."
        ),
        LearnCard(
            id: "cloud-batching",
            track: .cloud,
            visual: .stack,
            title: "BATCHING",
            hook: "The single biggest lever on GPU cost.",
            body: """
            A GPU serving one request at a time is mostly idle — it's waiting on memory, not maths. Batch 32 requests together and throughput rises nearly linearly while latency barely moves.

            Continuous (in-flight) batching goes further: instead of waiting for a whole batch to finish, finished sequences drop out and new requests slot in immediately. This is the core trick in vLLM.

            Practical consequence: your cost per token can differ by 10× between a naive server and a properly batched one running identical hardware and model.
            """,
            terms: ["Static batching", "Continuous batching", "PagedAttention", "GPU utilization"],
            action: "Load-test an endpoint at 1 vs 50 concurrent requests. Compare tokens/sec per dollar."
        ),
        LearnCard(
            id: "cloud-gpu",
            track: .cloud,
            visual: .curve,
            title: "GPU ECONOMICS",
            hook: "Know what you're actually paying for.",
            body: """
            VRAM decides what you can run; bandwidth decides how fast it runs. Rough sizing: parameters × 2 bytes for FP16 weights, plus KV cache that grows with batch size and context length. A 7B model needs ~14GB before you've served a single user.

            Options ladder from cheapest to most flexible: serverless per-token APIs (no ops, great until volume), rented GPUs by the hour (RunPod, Lambda), then reserved cloud instances (cheapest per hour, you eat the idle time).

            Most teams over-provision. Measure real utilization before you commit to a reservation.
            """,
            terms: ["VRAM", "KV cache", "Memory bandwidth", "Spot instance", "Cold start"],
            action: "Compute the VRAM needed for a 13B model at 4-bit with 8k context. Practice the arithmetic."
        ),
        LearnCard(
            id: "cloud-serverless",
            track: .cloud,
            visual: .cluster,
            title: "SERVERLESS INFERENCE",
            hook: "Scale to zero, pay per call — with a catch.",
            body: """
            Serverless GPU platforms (Modal, Replicate, Bedrock, SageMaker Serverless) spin capacity up on demand and bill only for what you use. Perfect for spiky or early-stage workloads.

            The catch is cold starts. Loading a multi-gigabyte model into GPU memory takes seconds to minutes. Mitigations: keep-warm instances, smaller models, or streaming weights.

            Rule of thumb: bursty and unpredictable → serverless. Steady 24/7 traffic → dedicated is cheaper past a surprisingly low threshold.
            """,
            terms: ["Cold start", "Scale to zero", "Keep-warm", "Provisioned concurrency"],
            action: "Time a cold start on a serverless GPU platform, then a warm one. Budget accordingly."
        ),
        LearnCard(
            id: "cloud-containers",
            track: .cloud,
            visual: .stack,
            title: "CONTAINERS & K8S",
            hook: "\"Works on my machine\" doesn't survive a GPU driver.",
            body: """
            ML environments are famously fragile — CUDA versions, driver versions, framework versions all have to agree. Docker pins the whole stack so it runs identically everywhere.

            Kubernetes then handles many containers across many machines: scheduling GPU pods, autoscaling on load, rolling out new model versions without downtime, restarting what crashes.

            You don't need to master K8s to be an AI engineer, but you should be able to read a Dockerfile, build an image with a pinned CUDA base, and understand what a deployment and a service do.
            """,
            terms: ["Dockerfile", "CUDA base image", "Pod", "HPA", "Rolling update"],
            action: "Containerize one inference script with a pinned CUDA base image and run it somewhere else."
        ),
        LearnCard(
            id: "cloud-caching",
            track: .cloud,
            visual: .pipeline,
            title: "CACHING",
            hook: "The cheapest token is the one you never generate.",
            body: """
            Three layers, all worth having. Exact-match cache: identical prompt, return the stored response — free and instant. Semantic cache: embed the query and reuse the answer if a near-identical question was asked before. Prompt cache: providers charge much less for a repeated prefix, so putting your long static system prompt first is real money.

            Semantic caching needs a similarity threshold you actually tune — too loose and users get answers to questions they didn't ask.

            On a support bot with repetitive questions, caching routinely cuts cost by half.
            """,
            terms: ["Prompt caching", "Semantic cache", "TTL", "Cache hit rate"],
            action: "Log your prompts for a week and count exact duplicates. The number is usually surprising."
        ),
        LearnCard(
            id: "cloud-observability",
            track: .cloud,
            visual: .network,
            title: "OBSERVABILITY",
            hook: "You cannot debug what you didn't log.",
            body: """
            LLM apps fail quietly — no stack trace, just a slightly wrong answer. So trace everything: the full prompt, the retrieved context, the raw completion, token counts, latency per step, and which model version served it.

            Tools like LangSmith, Langfuse, Phoenix and Helicone give you this plus a UI to filter the bad ones. Cheap alternative: structured JSON logs with a trace ID threading the whole request.

            The payoff is that "the bot gave a weird answer yesterday" becomes a lookup instead of an archaeology project.
            """,
            terms: ["Trace", "Span", "Token accounting", "Langfuse", "p95 latency"],
            action: "Add a trace ID to every LLM call and log the prompt, context, and response together."
        ),
        LearnCard(
            id: "cloud-mlops",
            track: .cloud,
            visual: .pipeline,
            title: "PROMPTS ARE CODE",
            hook: "Version them like it.",
            body: """
            A prompt change can break production as badly as a code change, yet teams routinely edit them in a dashboard with no review and no history. Put prompts in version control, tag them, and log which version produced which output.

            Then gate changes on your eval suite in CI: prompt edited → tests run → merge blocked on regression. Same discipline as any other deploy.

            Add feature flags or A/B routing so you can ship a new prompt to 5% of traffic and compare before committing.
            """,
            terms: ["Prompt versioning", "CI gate", "Canary", "Model registry", "Rollback"],
            action: "Move your prompts out of the dashboard and into a repo file today."
        ),
        LearnCard(
            id: "cloud-security",
            track: .cloud,
            visual: .stack,
            title: "SECURITY BASICS",
            hook: "The prompt is an attack surface.",
            body: """
            Prompt injection is the headline risk: untrusted text — a web page, a PDF, an email — carries instructions that your model then follows. There is no complete fix. You reduce blast radius instead: least-privilege tools, human confirmation for destructive actions, and treating all retrieved content as data rather than instructions.

            Also standard hygiene: never put API keys in the client, rate-limit per user, strip PII before it leaves your systems, and know your provider's data-retention terms.

            Assume anything in the context window can leak into the output.
            """,
            terms: ["Prompt injection", "Least privilege", "PII redaction", "Data retention"],
            action: "Try to make your own app misbehave with an injected instruction in a document."
        )
    ]

    // MARK: - NLP

    static let nlp: [LearnCard] = [
        LearnCard(
            id: "nlp-bpe",
            track: .nlp,
            visual: .tokens,
            title: "BYTE-PAIR ENCODING",
            hook: "How the vocabulary gets built.",
            body: """
            BPE starts with individual characters and repeatedly merges the most frequent adjacent pair. Do that 50,000 times and you get a vocabulary where common words are single tokens and rare words break into reusable pieces.

            This elegantly solves the out-of-vocabulary problem: any string can be encoded, worst case character by character. It's why models handle typos and invented words at all.

            Consequence worth knowing: languages underrepresented in the training corpus get chopped into far more tokens, so they cost more and effectively get less context.
            """,
            terms: ["BPE", "WordPiece", "SentencePiece", "OOV", "Vocabulary size"],
            action: "Tokenize the same sentence in English and another language. Compare the counts."
        ),
        LearnCard(
            id: "nlp-embeddings-history",
            track: .nlp,
            visual: .vectors,
            title: "WORD2VEC → BERT",
            hook: "How embeddings learned about context.",
            body: """
            Word2Vec (2013) gave each word one fixed vector, learned from the company it keeps. Famously king − man + woman ≈ queen. But "bank" got a single vector averaging riverbank and financial institution.

            ELMo and BERT (2018) made embeddings contextual — the vector for "bank" now depends on the sentence around it. BERT trained by masking random words and predicting them, which forces it to read both directions at once.

            Modern sentence-embedding models are descendants of this line, and they're what your RAG pipeline runs on.
            """,
            terms: ["Word2Vec", "Contextual embedding", "BERT", "MLM", "Bidirectional"],
            action: "Compare Word2Vec and a BERT-based model on a sentence with an ambiguous word."
        ),
        LearnCard(
            id: "nlp-classification",
            track: .nlp,
            visual: .cluster,
            title: "CLASSIFICATION",
            hook: "Still the highest-ROI NLP task in industry.",
            body: """
            Routing tickets, tagging sentiment, flagging spam, detecting intent — enormous amounts of real business value are just text classification.

            You now have three tiers. Zero-shot with an LLM: instant, no data, most expensive per call. Fine-tuned small model (DistilBERT and friends): needs a few hundred labelled examples, then runs in milliseconds for near-zero cost. Classic TF-IDF plus logistic regression: still shockingly competitive on narrow domains.

            Reach for the LLM to bootstrap labels, then distil into a small model for production volume.
            """,
            terms: ["Zero-shot", "Fine-tuning", "F1 score", "Class imbalance", "Distillation"],
            action: "Label 200 examples with an LLM, train a DistilBERT on them, compare cost per 1k calls."
        ),
        LearnCard(
            id: "nlp-ner",
            track: .nlp,
            visual: .tokens,
            title: "NAMED ENTITY RECOGNITION",
            hook: "Pulling structure out of prose.",
            body: """
            NER tags spans of text as people, organizations, dates, amounts, diagnoses — whatever your schema needs. It's the backbone of document processing, resume parsing, and medical and legal extraction.

            Traditionally a token classification model with BIO tagging (Begin, Inside, Outside). Today an LLM with a JSON schema often matches it with zero training data — but costs more and needs validation that the JSON is well-formed.

            Hybrid works well: LLM extracts, code validates against a schema, low-confidence cases go to a human.
            """,
            terms: ["BIO tagging", "Span", "spaCy", "Structured output", "Schema validation"],
            action: "Extract entities from 10 documents with both spaCy and an LLM. Compare errors, not just scores."
        ),
        LearnCard(
            id: "nlp-metrics",
            track: .nlp,
            visual: .curve,
            title: "EVALUATION METRICS",
            hook: "Know what each number can and can't tell you.",
            body: """
            Perplexity: how surprised the model is by real text. Lower is better, comparable only between models sharing a tokenizer. BLEU and ROUGE: n-gram overlap with a reference, from translation and summarization respectively — they reward matching words, not matching meaning.

            That's the core weakness. A perfect paraphrase scores badly; a fluent wrong answer that reuses the reference's vocabulary scores well.

            Modern practice leans on embedding-based scores (BERTScore) and model-as-judge, validated against human ratings on a sample.
            """,
            terms: ["Perplexity", "BLEU", "ROUGE", "BERTScore", "Inter-annotator agreement"],
            action: "Score a good paraphrase with ROUGE. Watch a correct answer get punished."
        ),
        LearnCard(
            id: "nlp-seq2seq",
            track: .nlp,
            visual: .pipeline,
            title: "SEQ2SEQ",
            hook: "Text in, text out — the framing that unified NLP.",
            body: """
            Translation, summarization, question answering and grammar correction all became the same problem: map an input sequence to an output sequence. T5 pushed this to its conclusion by prefixing every task with an instruction like "translate English to German:".

            That reframing is the direct ancestor of prompting. When you write "summarize this in three bullets", you're using the same idea — the instruction is part of the input.

            Encoder-decoder models still win on tasks with a fixed input to transform; decoder-only models won everything open-ended.
            """,
            terms: ["Encoder-decoder", "T5", "Teacher forcing", "Beam search"],
            action: "Run the same summarization on a T5 model and a chat model. Note the different failure styles."
        ),
        LearnCard(
            id: "nlp-preprocessing",
            track: .nlp,
            visual: .pipeline,
            title: "PREPROCESSING",
            hook: "Most of the job, and nobody posts about it.",
            body: """
            Real text is a mess: PDFs with two-column layouts, HTML boilerplate, OCR noise, mixed encodings, duplicated content. Garbage in the index means garbage retrieved, and no model fixes that.

            The old pipeline (lowercase, stopword removal, stemming) is mostly obsolete for transformer models — they want the original text. What still matters enormously: clean extraction, deduplication, encoding normalization, and preserving document structure like headings and tables.

            For PDFs specifically, layout-aware extraction beats naive text dumping by a wide margin.
            """,
            terms: ["Deduplication", "Unicode normalization", "Layout-aware parsing", "Boilerplate removal"],
            action: "Extract text from a two-column PDF naively, then with a layout-aware tool. Compare."
        ),
        LearnCard(
            id: "nlp-transfer",
            track: .nlp,
            visual: .stack,
            title: "TRANSFER LEARNING",
            hook: "Why you never start from scratch.",
            body: """
            Pretrain once on a mountain of general text, then adapt cheaply to your specific task. The base model already knows syntax, facts and world structure; fine-tuning only teaches it your format and domain.

            This is why 500 well-chosen labelled examples can beat 50,000 mediocre ones, and why training from random initialization is almost never right outside of research.

            The modern version of this instinct: try prompting first, then few-shot examples, then retrieval, and only fine-tune when you've proven the cheaper options can't get there.
            """,
            terms: ["Pretraining", "Fine-tuning", "Few-shot", "Catastrophic forgetting", "Domain adaptation"],
            action: "Before your next fine-tune, try few-shot prompting on the same task and measure the gap."
        )
    ]
}
