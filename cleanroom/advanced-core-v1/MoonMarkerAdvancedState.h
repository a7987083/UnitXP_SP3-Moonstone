#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

#include "Vanilla1121_functions.h"

namespace moonMarkerAdvancedState {

constexpr std::uint32_t kSchemaVersion = 1;
constexpr std::size_t kMaxTeamMarkers = 16;
constexpr std::size_t kMaxModelPathLength = 240;
constexpr std::size_t kMaxOwnerNameLength = 48;
constexpr float kMinScale = 0.10f;
constexpr float kMaxScale = 5.00f;
constexpr float kMinTopHeight = 0.0f;
constexpr float kMaxTopHeight = 20.0f;
constexpr float kDefaultMaxDistance = 80.0f;
constexpr float kAbsoluteMaxDistance = 120.0f;
constexpr std::uint32_t kRateLimitPerSecond = 8;

struct MarkerTransform {
    C3Vector position = {};
    float scale = 1.0f;
    float yawDegrees = 0.0f;
};

struct TopModelDefinition {
    bool enabled = false;
    std::string path;
    float scale = 1.0f;
    float yawDegrees = 0.0f;
    float height = 3.0f;
};

struct MarkerDefinition {
    std::uint32_t id = 0;
    std::uint32_t revision = 0;
    std::uint32_t sequence = 0;
    std::uint32_t mapId = 0;
    bool localOnly = true;
    std::string primaryPath;
    MarkerTransform primary;
    TopModelDefinition top;
    std::string owner;
    std::string lastEditor;
    std::uint32_t createdTick = 0;
    std::uint32_t updatedTick = 0;
};

enum class ValidationCode {
    Ok,
    AccessDenied,
    ModelPathRequired,
    ModelPathTooLong,
    AbsoluteModelPath,
    ParentPathTraversal,
    InvalidPathCharacter,
    UnsupportedModelExtension,
    PositionNotFinite,
    ScaleNotFinite,
    ScaleOutOfRange,
    YawNotFinite,
    TopHeightNotFinite,
    TopHeightOutOfRange,
    DistanceExceeded,
    MarkerIdOutOfRange,
    MarkerLimitReached,
    OwnerRequired,
    OwnerTooLong,
    SequenceRequired,
    SequenceStale,
    RateLimited,
    MarkerNotFound,
};

struct ValidationResult {
    ValidationCode code = ValidationCode::Ok;
    const char* name = "OK";

    explicit operator bool() const { return code == ValidationCode::Ok; }
};

struct Status {
    bool localDraftActive = false;
    std::size_t teamMarkerCount = 0;
    std::size_t maxTeamMarkers = kMaxTeamMarkers;
    std::uint64_t acceptedMutations = 0;
    std::uint64_t rejectedValidation = 0;
    std::uint64_t rejectedAccess = 0;
    std::uint64_t rejectedRate = 0;
    std::uint64_t rejectedSequence = 0;
    std::uint64_t worldContextResets = 0;
    std::uintptr_t worldContextToken = 0;
    std::string lastError = "NOT_INITIALIZED";
};

const char* validationCodeName(ValidationCode code);
ValidationResult normalizeModelPath(const std::string& input, std::string& output);
ValidationResult normalizeAndValidate(MarkerDefinition& marker,
                                      bool requireTeamId,
                                      const C3Vector* actorPosition,
                                      float maxDistance);

ValidationResult commitLocalDraft(MarkerDefinition marker,
                                  bool guildAuthorized,
                                  const C3Vector* actorPosition,
                                  float maxDistance = kAbsoluteMaxDistance);
bool getLocalDraft(MarkerDefinition& marker);
void clearLocalDraft(const char* reason);

ValidationResult acceptTeamMutation(const std::string& sender,
                                    std::uint32_t markerId,
                                    std::uint32_t sequence,
                                    bool publisherAuthorized,
                                    std::uint32_t nowTick);
ValidationResult upsertTeamMarker(MarkerDefinition marker,
                                  bool publisherAuthorized,
                                  const C3Vector* actorPosition,
                                  float maxDistance = kDefaultMaxDistance);
ValidationResult removeTeamMarker(std::uint32_t markerId,
                                  bool publisherAuthorized);
bool getTeamMarker(std::uint32_t markerId, MarkerDefinition& marker);

void clearTeamMarkers(const char* reason);
void clearAll(const char* reason);
void observeWorldContext(std::uintptr_t contextToken);
Status status();

bool runSelfTest(std::size_t& passed, std::size_t& total,
                 std::string& firstFailure);

} // namespace moonMarkerAdvancedState
