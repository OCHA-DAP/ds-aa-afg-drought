# Logistic Regression, CDI, and Probability: Technical Explainer

This document explains the relationship between the Combined Drought Index (CDI), logistic regression predictions, and when to use each.

## How Logistic Regression Works

Logistic regression does **not** fit a linear regression first and then transform. It directly estimates coefficients via maximum likelihood estimation (MLE).

### The Model Structure

1. **Linear predictor**: z = β₀ + β₁x₁ + β₂x₂ + ... (unbounded, any real number)
2. **Logistic transformation**: p = 1 / (1 + exp(-z)) (fixed S-curve, maps to 0-1)
3. **Predicted probability**: P(drought | X) = p

### The Logistic Function is Fixed

The logistic function itself is always the same:

```
f(z) = 1 / (1 + exp(-z))
```

It's not learned or fitted - just a fixed mathematical transformation. What gets learned are the **coefficients** (β values).

### Maximum Likelihood Estimation

MLE finds coefficients that maximize the probability of observing the actual outcomes.

For each observation:
- If y=1 (drought): we want p high → likelihood contribution = p
- If y=0 (no drought): we want p low → likelihood contribution = (1-p)

Total likelihood = product across all observations. MLE finds β values that maximize this.

**Contrast with linear regression:**
- Linear regression minimizes squared error: Σ(y - ŷ)²
- This treats 0/1 as numbers on a continuous scale
- Doesn't "know" that p=0.01 vs p=0.001 are both good for non-drought

For binary outcomes, likelihood is the correct objective.

## CDI vs Linear Predictor vs Probability

### The Three Quantities

| Quantity | Formula | Range | Properties |
|----------|---------|-------|------------|
| Linear predictor | β₀ + β₁x₁ + β₂x₂ + ... | (-∞, +∞) | Additive, interpretable weights |
| CDI | (β₁x₁ + β₂x₂ + ...) / Σ\|β\| | Unbounded | Normalized linear predictor, no intercept |
| Probability | 1 / (1 + exp(-linear_predictor)) | (0, 1) | Non-linear transform |

### Key Relationships

- **CDI vs Linear Predictor**: Perfectly correlated (r = 1). CDI is just shifted (no intercept) and scaled (normalized).
- **CDI vs Probability**: Highly correlated (r ≈ 0.96) but not perfectly linear due to S-curve.
- **Rankings**: Identical across all three. Same years trigger at any percentile threshold.

### Why the Correlation Isn't 1.0 for Probability

The logistic function is an S-curve:
- In the middle (z ≈ 0, p ≈ 0.5): steep slope, small z changes → large p changes
- At extremes (z very positive/negative): flat slope, large z changes → small p changes

This compression at extremes reduces the Pearson correlation from 1.0 to ~0.96.

## Why CDI Weights Don't Translate to Probability Space

### The Problem: Non-Linear Contributions

In linear predictor space, weights are additive and constant:
- If VHI increases by 1 unit, CDI increases by β_VHI (always)

In probability space, the contribution depends on where you are on the curve:
- At p ≈ 0.5: a unit increase in VHI has **maximum** effect on probability
- At p ≈ 0.9: the same increase has **minimal** effect (near the ceiling)

There's no fixed "weight" in probability space - contributions are context-dependent.

### Alternatives in Probability Space

1. **Odds ratios**: exp(β) = multiplicative change in odds per unit increase. Constant, but odds aren't intuitive.

2. **Average marginal effects**: Compute ∂p/∂x for each observation, then average. Single number per predictor, but it's an average.

3. **Marginal effects at the mean**: Compute ∂p/∂x when all predictors are at their mean values.

None of these are as clean as CDI weights.

## When to Use CDI vs Probability

### Use CDI when:

- Setting percentile-based thresholds (e.g., RP=4 = 75th percentile)
- Communicating drought severity on an interpretable scale
- Rankings and relative ordering matter
- You want simple, constant weights (VHI 34%, mixed_fcast 28%, etc.)

### Use Probability when:

- Communicating risk as a percentage ("65% chance of drought")
- Decision-making with explicit cost-benefit analysis
- Combining forecasts from multiple models
- Calibration has been verified

### For This Application

We use CDI because:
1. We use percentile thresholds (RP=4), not probability cutoffs
2. CDI weights are interpretable and constant
3. We don't communicate probabilistic forecasts to partners
4. Rankings are identical, so same years trigger either way

## Probability Interpretation

The predicted probability has a specific meaning:

**P(drought) = probability that end-of-season ASI will exceed the 4-year return period threshold**

This is meaningful, but:
1. Calibration is assumed, not verified (n=42, regularized model)
2. Our operational framework uses percentiles, not probabilities
3. CDI is more interpretable for this use case

## Summary

- Logistic regression fits coefficients via MLE, not by fitting linear regression then transforming
- The logistic function is fixed; coefficients are learned
- CDI is mathematically equivalent to the linear predictor (r=1), just normalized
- Probability is a non-linear (S-curve) transform of the linear predictor (r≈0.96)
- Rankings are identical across CDI and probability
- CDI weights are clean and constant; probability contributions vary by context
- For percentile-based triggering, CDI is preferred
