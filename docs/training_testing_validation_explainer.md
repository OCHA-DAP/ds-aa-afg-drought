# Training, Testing, and Validation: A Beginner's Guide

This document explains how we validate the drought trigger model and why we use different processes at different stages.

## The Problem

We have 42 years of data. We want to build a model that predicts drought. But how do we know if the model actually works?

**The trap**: If we build the model using all 42 years, then test it on those same 42 years, it will look great - but that's cheating. The model already "saw" the answers.

**The goal**: Estimate how well the model will work on *future* years it has never seen.

---

## The Simple Idea: Hold Out Some Data

Imagine you're studying for an exam:
- You have 42 practice problems with answers
- If you memorize the answers and someone tests you on those same problems, you'll ace it
- But that doesn't mean you learned anything

Better approach:
- Study with 41 problems
- Test yourself on the 1 problem you didn't study
- That tells you if you actually learned the pattern

This is the core idea behind all validation.

---

## Three Processes We Use

### 1. Bootstrap CV: For Making Decisions During Development

**What it does**: Creates many "practice exams" by randomly reshuffling the data.

**When we use it**:
- Deciding which predictors to include
- Choosing the regularization strength
- Comparing different model approaches

**Analogy**: Like doing lots of practice tests while studying to figure out what study techniques work best.

### 2. LOOCV: For Honest Final Performance

**What it does**:
- Remove year 1, build model on years 2-42, predict year 1
- Remove year 2, build model on years 1 & 3-42, predict year 2
- ... repeat for all 42 years

**When we use it**: Getting the final performance numbers we report.

**Why it's honest**: Each prediction is made by a model that *never saw that year*. No cheating possible.

**Analogy**: Like taking 42 separate final exams, where each time you studied everything except the questions on that exam.

### 3. Full Dataset Fit: For the Actual Trigger

**What it does**: Build the final model using all 42 years.

**When we use it**: Creating the actual CDI weights we'll use in 2026.

**Why use all data?**: LOOCV told us how well the model works. Now we want the best possible model for actual use - more data = better estimates.

**Analogy**: After the exams are done and you know you learned the material, you go back and study everything one more time before the real thing.

---

## How Bootstrap and LOOCV Actually Work

### LOOCV (systematic, exact)

```
Round 1: Train on years 2-42, test on year 1
Round 2: Train on years 1, 3-42, test on year 2
Round 3: Train on years 1-2, 4-42, test on year 3
...
Round 42: Train on years 1-41, test on year 42
```

- Every year gets tested exactly once
- Every year is held out exactly once
- Very structured

### Bootstrap (random, repeated)

```
Round 1: Randomly pick 42 years WITH REPLACEMENT
         Maybe get: [1984, 1984, 1986, 1988, 1988, 1988, 1990, ...]
         Some years appear 2-3 times, some not at all
         Test on the years that weren't picked

Round 2: Randomly pick another 42 years WITH REPLACEMENT
         Different random selection...

... repeat 30 times, average the results
```

**"With replacement"** means after you pick a year, you put it back and might pick it again.

### Visual example with 5 years

**LOOCV:**
```
Fold 1: Train [B,C,D,E]  Test [A]
Fold 2: Train [A,C,D,E]  Test [B]
Fold 3: Train [A,B,D,E]  Test [C]
Fold 4: Train [A,B,C,E]  Test [D]
Fold 5: Train [A,B,C,D]  Test [E]
```

**One bootstrap sample:**
```
Original data: [A, B, C, D, E]
Random picks:  [B, B, D, E, E]  (picked B twice, E twice, skipped A and C)
Train on:      [B, B, D, E, E]
Test on:       [A, C]  (the ones we didn't pick)
```

### Why use bootstrap instead of LOOCV sometimes?

- Bootstrap is faster for trying many options
- LOOCV is more thorough but slower (42 complete model fits)
- We use bootstrap for exploration, LOOCV for final metrics

---

## What We Keep vs. Throw Away

Here's a key insight: **we fit dozens of models during validation and throw almost all of them away.**

| Process | Models fitted | What we KEEP | What we THROW AWAY |
|---------|---------------|--------------|-------------------|
| Bootstrap (30 rounds) | 30 models | Performance metrics (F1, etc.) | All 30 sets of coefficients |
| LOOCV (42 folds) | 42 models | Performance metrics | All 42 sets of coefficients |
| Full data fit | 1 model | **The coefficients (CDI weights)** | Nothing |

The bootstrap and LOOCV models exist only to answer: "How well does this approach work?"

The **only coefficients we keep** are from the final full-data fit. Those become the CDI weights.

---

## The Key Assumption

We assume the full-data model will behave similarly to the LOOCV models:

> "The 42 models trained on 41 years each achieved F1 ≈ 0.82. Therefore, the 1 model trained on all 42 years should perform similarly on future data."

**When this assumption is reasonable:**
- Coefficients are stable across LOOCV folds (don't jump around wildly)
- Ridge regularization helps - prevents any single year from having outsized influence
- The 42 years cover a representative range of conditions

**When it might not hold:**
- Future conditions are very different from 1984-2025 (climate change?)
- The model is unstable (coefficients vary dramatically between folds)

---

## "But Doesn't the Full-Data Model Overfit?"

This is a common concern. Here's the nuance:

**What overfitting means:**
- Model learns real signal + noise
- Performs great on training data
- Performs worse on new data

**What happens with our full-data fit:**
- Yes, it memorizes some noise
- Its in-sample performance would be inflated (maybe F1 = 0.95)
- But **we don't use or report that number**

**The key distinction:**

| What we use the full-data model for | Overfitting problem? |
|-------------------------------------|---------------------|
| Claiming "this model has F1 = 0.95" | YES - that's misleading |
| Extracting coefficients for deployment | NO - these are our best estimates |

We already know from LOOCV that true performance is ~0.82. The full-data coefficients are still valid - actually *better* estimates than any single LOOCV fold because they use more data. We just can't trust the in-sample metrics.

**Regularization also helps**: Ridge penalty = "don't let any coefficient get too extreme." This directly limits how much noise the model can memorize.

---

## Why Not Keep the LOOCV/Bootstrap Models?

People do sometimes extract or aggregate coefficients from CV folds. A few approaches:

### Average coefficients across folds

Take the mean of all 42 LOOCV coefficient sets.

**Why do it**: Averages out noise from any single fold

**Why we don't**: With regularization, the full-data coefficients are usually almost identical to the averaged fold coefficients anyway. Adds complexity without much benefit.

### Ensemble / model averaging

Keep all 42 models. When predicting a new year, run all 42 and average their predictions.

**Why do it**: More robust predictions, reduces variance

**Why we don't**:
- Now you have 42 models to maintain
- Harder to explain ("what are the CDI weights?" becomes complicated)
- We want one interpretable formula for partners

### The trade-off

| Approach | Generalization | Interpretability | Simplicity |
|----------|---------------|------------------|------------|
| Single full-data model | Good (with regularization) | High | Simple |
| Averaged coefficients | Slightly better | High | Simple |
| Ensemble (keep all models) | Best | Low | Complex |

For an operational drought trigger that needs to be explained to partners, the single model wins on interpretability.

---

## Summary

```
Step 1: Bootstrap CV
   "Which approach works best?"
   → Fit 30+ models, throw away coefficients, keep performance comparisons

Step 2: LOOCV
   "How well does this approach actually work?"
   → Fit 42 models, throw away coefficients, keep predictions
   → Produces: F1 = 0.82, Precision = 90%, Recall = 75%
   → THESE ARE THE NUMBERS WE REPORT

Step 3: Full Dataset Fit
   "Give me the final model for real use"
   → Fit 1 model, keep coefficients
   → Produces: CDI weights (VHI 34%, mixed_fcast 28%, etc.)
   → THIS IS WHAT WE DEPLOY
```

**Key points:**
1. These processes are independent - LOOCV doesn't use bootstrap results
2. LOOCV metrics are what we report - they're the honest estimate
3. Full dataset model is what we deploy - but we already know its expected performance
4. Some overfitting happens in the full model, but regularization limits it and we don't trust its in-sample metrics anyway
