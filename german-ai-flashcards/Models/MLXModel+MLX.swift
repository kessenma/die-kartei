//
//  MLXModel+MLX.swift
//  german-ai-flashcards
//
//  The MLX side of the model catalog: the registry configuration for each `MLXModel`.
//  The catalog itself (ModelConfiguration.swift) is Foundation-only so the Android core shares it.
//

import Foundation
import MLXLLM
import MLXLMCommon

extension MLXModel {
    /// The MLX registry configuration for this model, from its `repoID`.
    var configuration: ModelConfiguration { ModelConfiguration(id: repoID) }
}
