"""Polynomial models and prediction metrics."""

import itertools
import math
import numpy as np
from .config import MIN_RESIDUAL_DF
from .preparation import is_constant


class FitError(ValueError):
    pass

def constant_terms(n_features):
    return [tuple([0] * n_features)]

def linear_terms(n_features):
    powers = constant_terms(n_features)
    for j in range(n_features):
        term = [0] * n_features
        term[j] = 1
        powers.append(tuple(term))
    return powers


def interaction_terms(n_features):
    powers = linear_terms(n_features)
    for i, j in itertools.combinations(range(n_features), 2):
        term = [0] * n_features
        term[i] = term[j] = 1
        powers.append(tuple(term))
    return powers


def quadratic_terms(n_features):
    powers = interaction_terms(n_features)
    for j in range(n_features):
        term = [0] * n_features
        term[j] = 2
        powers.append(tuple(term))
    return powers


""" Functional Strategy pattern, using different model forms for polynomial regression """

TERM_BUILDERS = {
    "constant": constant_terms,
    "linear": linear_terms,
    "interaction": interaction_terms,
    "quadratic": quadratic_terms,
}

def powers_for(n_features, form):
    try:
        strategy = TERM_BUILDERS[form]
    except KeyError as exc:
        raise FitError(f"Unknown model form {form!r}; choose from {tuple(TERM_BUILDERS)}") from exc
    return strategy(n_features)

def model_matrix(values, powers):
    return np.column_stack([np.prod(values ** np.asarray(p), axis=1) for p in powers])

def fit_polynomial(X, y, form):
    """Fit least squares to a numeric N-by-q input matrix and N responses.
    """
    X, y = np.asarray(X, float), np.asarray(y, float)
    center, scale = X.mean(axis=0), X.std(axis=0)
    scale = np.where(scale > 1e-12, scale, 1.0)
    powers = powers_for(X.shape[1], form)
    matrix = model_matrix((X - center) / scale, powers)
    if len(y) < matrix.shape[1] + MIN_RESIDUAL_DF:
        raise FitError("insufficient residual degrees of freedom")
    rank = np.linalg.matrix_rank(matrix)
    condition = np.linalg.cond(matrix)
    if rank != matrix.shape[1] or condition > 1e10:
        raise FitError("rank deficient or ill-conditioned model matrix")
    coefs = np.linalg.lstsq(matrix, y, rcond=None)[0]
    return {"form": form, "center": center, "scale": scale, "powers": powers,
            "coefficients": coefs, "rank": rank, "condition_number": condition}

def predict_polynomial(model, X):
    """Return predictions using the fitted model's stored scaling and powers."""
    values = (np.asarray(X, float) - model["center"]) / model["scale"]
    return model_matrix(values, model["powers"]) @ model["coefficients"]

def model_expression(model, features):
    """Return a Python arithmetic expression using the fitted standardized inputs."""
    terms = []
    for coefficient, power in zip(model["coefficients"], model["powers"]):
        term = f"({coefficient:.12g})"
        for j, exponent in enumerate(power):
            if exponent:
                term += f"*((({features[j]})-({model['center'][j]:.12g}))/({model['scale'][j]:.12g}))**{exponent}"
        terms.append(term)
    return " + ".join(terms)


def raw_model_terms(model, features):
    expanded = {}
    for coefficient, power in zip(model["coefficients"], model["powers"]):
        for exponent in itertools.product(*(range(p + 1) for p in power)):
            value = float(coefficient)
            for j, (p, k) in enumerate(zip(power, exponent)):
                value *= math.comb(p, k) * (-model["center"][j]) ** (p - k) / model["scale"][j] ** p
            expanded[exponent] = expanded.get(exponent, 0.0) + value
    rows = []
    for exponent, coefficient in sorted(expanded.items(), key=lambda item: (sum(item[0]), item[0])):
        term = "*".join(feature if power == 1 else f"{feature}**{power}"
                        for feature, power in zip(features, exponent) if power) or "1"
        rows.append({"term": term, "coefficient": coefficient})
    expression = " + ".join(f"({row['coefficient']:.12g})" + ("*" + row["term"] if row["term"] != "1" else "")
                            for row in rows)
    return rows, expression

def score_predictions(y, prediction):
    y, prediction = np.asarray(y, float), np.asarray(prediction, float)
    mse = np.mean((y - prediction) ** 2)
    denom = np.sum((y - y.mean()) ** 2)
    y_range = np.ptp(y)
    return {"r2": 1 - np.sum((y - prediction) ** 2) / denom if not is_constant(y) else np.nan,
            "rmse": np.sqrt(mse), "mae": np.mean(np.abs(y - prediction)),
            "nrmse": np.sqrt(mse) / y_range if y_range > 1e-12 else np.nan}
