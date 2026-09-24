import SwiftData

/// Every `@Model` type in the store, in one place. The app's container and the DEBUG sync round
/// trip (`SyncDebugVerify`) must build from the same list.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        SavedDeck.self, SavedCard.self, QuizResult.self,
        ChatConversation.self, ChatMessage.self,
        StudyPaper.self,
        StudyStory.self,
        LearnedPhrase.self,
        LearnerProfile.self, ArchivedMemoryItem.self,
        StudyDay.self,
        MatchingPairStat.self, MatchingRound.self,
        ArticleWordStat.self, ArticleRound.self,
        PrepositionStat.self, PrepositionRound.self,
        StoryReadingSession.self, StoryQuizAttempt.self,
        BatchJob.self,
        JobPosting.self,
        ClassCourse.self, ClassEntry.self, ClassMaterial.self,
        // Local-only iCloud Sync bookkeeping (never synced itself).
        SyncRecordState.self, SyncMeta.self,
    ]
}
