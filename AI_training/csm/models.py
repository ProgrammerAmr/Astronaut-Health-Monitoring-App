"""
Candidate tabular baseline models and multi-formulation wrappers for DEC-001.

Implements audited candidate families (NO final architecture pre-selected):
    Tier 0:
        - dummy_majority: Majority-class baseline (imbalance sanity floor)
        - logreg_balanced: Class-weighted L2 Logistic Regression
    Tier 1:
        - rf_balanced: Balanced Random Forest (replicates Harrivel et al., 2017 family)
        - gbdt_balanced: Regularized Gradient Boosted Trees (XGBoost if available,
          otherwise scikit-learn HistGradientBoostingClassifier with balanced sample weights)

Implements all three audited label formulations:
    - multiclass: Single 4-class softmax classifier (Baseline, CA, DA, SS)
    - binary_per_state: 3 independent One-vs-Rest detectors (CA, DA, SS vs. Baseline)
    - hierarchical: Stage 1 (Any-AHPLS vs. Baseline) -> Stage 2 (CA vs. DA vs. SS)

All preprocessing inside estimators (SimpleImputer + RobustScaler) is fitted
exclusively on the training fold passed to .fit().
"""

from __future__ import annotations

from typing import Dict, List, Literal, Optional, Sequence, Tuple

import numpy as np
from sklearn.base import BaseEstimator, ClassifierMixin
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import HistGradientBoostingClassifier, RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import RobustScaler
from sklearn.utils.class_weight import compute_sample_weight

from .constants import CLASS_TO_INDEX, TARGET_CLASSES

ModelName = Literal["dummy_majority", "logreg_balanced", "rf_balanced", "gbdt_balanced"]
FormulationName = Literal["multiclass", "binary_per_state", "hierarchical"]


def _make_base_estimator(model_name: ModelName, seed: int = 42) -> Pipeline:
    """Build a fold-local pipeline (SimpleImputer -> RobustScaler -> Estimator)."""
    if model_name == "dummy_majority":
        clf: BaseEstimator = DummyClassifier(strategy="prior")
        return Pipeline([("imputer", SimpleImputer(strategy="median")), ("clf", clf)])

    if model_name == "logreg_balanced":
        clf = LogisticRegression(
            C=0.5,
            class_weight="balanced",
            max_iter=1000,
            random_state=seed,
        )
        return Pipeline([
            ("imputer", SimpleImputer(strategy="median")),
            ("scaler", RobustScaler()),
            ("clf", clf),
        ])

    if model_name == "rf_balanced":
        clf = RandomForestClassifier(
            n_estimators=200,
            max_depth=8,
            min_samples_leaf=5,
            class_weight="balanced_subsample",
            n_jobs=-1,
            random_state=seed,
        )
        return Pipeline([
            ("imputer", SimpleImputer(strategy="median")),
            ("clf", clf),
        ])

    if model_name == "gbdt_balanced":
        try:
            from xgboost import XGBClassifier  # type: ignore

            clf = XGBClassifier(
                n_estimators=200,
                max_depth=4,
                learning_rate=0.05,
                subsample=0.8,
                colsample_bytree=0.8,
                reg_lambda=2.0,
                eval_metric="mlogloss",
                random_state=seed,
                n_jobs=4,
            )
        except ImportError:
            clf = HistGradientBoostingClassifier(
                max_iter=200,
                max_depth=4,
                learning_rate=0.05,
                min_samples_leaf=20,
                l2_regularization=2.0,
                random_state=seed,
            )
        return Pipeline([
            ("imputer", SimpleImputer(strategy="median")),
            ("clf", clf),
        ])

    raise ValueError(f"Unknown model_name: {model_name!r}")


def _fit_pipeline_balanced(pipe: Pipeline, X: np.ndarray, y: np.ndarray) -> Pipeline:
    """Fit pipeline, supplying balanced sample_weight when estimator lacks class_weight."""
    clf = pipe.named_steps["clf"]
    uses_sample_weight = isinstance(clf, HistGradientBoostingClassifier) or (
        clf.__class__.__name__ == "XGBClassifier"
    )
    if uses_sample_weight:
        sw = compute_sample_weight(class_weight="balanced", y=y)
        pipe.fit(X, y, clf__sample_weight=sw)
    else:
        pipe.fit(X, y)
    return pipe


def _align_proba(probs: np.ndarray, seen_classes: np.ndarray, n_classes: int) -> np.ndarray:
    """Expand estimator probabilities to fixed (N, n_classes) even if a training fold missed a class."""
    out = np.full((probs.shape[0], n_classes), 1e-6, dtype=np.float64)
    for col_i, cls_id in enumerate(seen_classes.tolist()):
        if 0 <= int(cls_id) < n_classes:
            out[:, int(cls_id)] = probs[:, col_i]
    out = out / np.sum(out, axis=1, keepdims=True)
    return out


class CSMModelWrapper(BaseEstimator, ClassifierMixin):
    """
    Unified DEC-001 model wrapper supporting:
        - formulation='multiclass' (4-class softmax)
        - formulation='binary_per_state' (3 independent One-vs-Rest heads: CA, DA, SS)
        - formulation='hierarchical' (Stage 1: Event vs Baseline -> Stage 2: CA/DA/SS)
    """

    def __init__(
        self,
        model_name: ModelName = "rf_balanced",
        formulation: FormulationName = "multiclass",
        seed: int = 42,
    ) -> None:
        self.model_name = model_name
        self.formulation = formulation
        self.seed = seed
        self.n_classes_ = len(TARGET_CLASSES)
        self._fitted_models: Dict[str, Pipeline] = {}

    def fit(self, X: np.ndarray, y: np.ndarray) -> "CSMModelWrapper":
        X_arr = np.asarray(X, dtype=np.float64)
        y_arr = np.asarray(y, dtype=np.int64)
        self._fitted_models = {}

        if self.formulation == "multiclass":
            pipe = _make_base_estimator(self.model_name, seed=self.seed)
            self._fitted_models["multiclass"] = _fit_pipeline_balanced(pipe, X_arr, y_arr)
            return self

        if self.formulation == "binary_per_state":
            for offset, cls_name in enumerate(("CA", "DA", "SS")):
                c_idx = CLASS_TO_INDEX[cls_name]
                y_bin = (y_arr == c_idx).astype(np.int64)
                if len(np.unique(y_bin)) < 2:
                    pipe = _make_base_estimator("dummy_majority", seed=self.seed + offset)
                else:
                    pipe = _make_base_estimator(self.model_name, seed=self.seed + offset)
                self._fitted_models[cls_name] = _fit_pipeline_balanced(pipe, X_arr, y_bin)
            return self

        if self.formulation == "hierarchical":
            base_idx = CLASS_TO_INDEX["Baseline"]
            y_event = (y_arr != base_idx).astype(np.int64)
            s1_name: ModelName = "dummy_majority" if len(np.unique(y_event)) < 2 else self.model_name
            pipe_s1 = _make_base_estimator(s1_name, seed=self.seed)
            self._fitted_models["stage1_event"] = _fit_pipeline_balanced(pipe_s1, X_arr, y_event)

            event_mask = y_arr != base_idx
            if np.sum(event_mask) >= 2 and len(np.unique(y_arr[event_mask])) >= 2:
                # Remap non-baseline classes {1, 2, 3} -> {0, 1, 2} cleanly for XGBoost compatibility
                y_s2 = y_arr[event_mask] - 1
                pipe_s2 = _make_base_estimator(self.model_name, seed=self.seed + 100)
                self._fitted_models["stage2_state"] = _fit_pipeline_balanced(
                    pipe_s2, X_arr[event_mask], y_s2
                )
            else:
                pipe_s2 = _make_base_estimator("dummy_majority", seed=self.seed + 100)
                fallback_y = np.zeros(max(1, int(np.sum(event_mask))), dtype=np.int64)
                fallback_x = X_arr[event_mask] if np.any(event_mask) else X_arr[:1]
                self._fitted_models["stage2_state"] = _fit_pipeline_balanced(
                    pipe_s2, fallback_x, fallback_y
                )
            return self

        raise ValueError(f"Unknown formulation: {self.formulation!r}")

    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        X_arr = np.asarray(X, dtype=np.float64)
        n = X_arr.shape[0]

        if self.formulation == "multiclass":
            pipe = self._fitted_models["multiclass"]
            raw = pipe.predict_proba(X_arr)
            seen = pipe.named_steps["clf"].classes_
            return _align_proba(raw, seen, self.n_classes_)

        if self.formulation == "binary_per_state":
            # Independent One-vs-Rest probabilities for CA, DA, SS; Baseline = prod(1 - p_k)
            p_states = np.zeros((n, 3), dtype=np.float64)
            for j, cls_name in enumerate(("CA", "DA", "SS")):
                pipe = self._fitted_models[cls_name]
                raw = pipe.predict_proba(X_arr)
                seen = pipe.named_steps["clf"].classes_.tolist()
                if 1 in seen:
                    p_states[:, j] = raw[:, seen.index(1)]
                else:
                    p_states[:, j] = 1e-6

            p_base = np.prod(1.0 - np.clip(p_states, 0.0, 0.999999), axis=1, keepdims=True)
            combined = np.hstack([p_base, p_states])
            combined = np.clip(combined, 1e-7, 1.0)
            return combined / np.sum(combined, axis=1, keepdims=True)

        if self.formulation == "hierarchical":
            pipe_s1 = self._fitted_models["stage1_event"]
            raw_s1 = pipe_s1.predict_proba(X_arr)
            seen_s1 = pipe_s1.named_steps["clf"].classes_.tolist()
            p_event = raw_s1[:, seen_s1.index(1)] if 1 in seen_s1 else np.full(n, 1e-6)
            p_base = 1.0 - p_event

            pipe_s2 = self._fitted_models["stage2_state"]
            raw_s2 = pipe_s2.predict_proba(X_arr)
            seen_s2 = pipe_s2.named_steps["clf"].classes_
            p_cond = _align_proba(raw_s2, seen_s2, 3)

            out = np.zeros((n, 4), dtype=np.float64)
            out[:, 0] = p_base
            out[:, 1:4] = p_event[:, None] * p_cond
            out = np.clip(out, 1e-7, 1.0)
            return out / np.sum(out, axis=1, keepdims=True)

        raise ValueError(f"Unknown formulation: {self.formulation!r}")

    def predict(self, X: np.ndarray) -> np.ndarray:
        return np.argmax(self.predict_proba(X), axis=1)
