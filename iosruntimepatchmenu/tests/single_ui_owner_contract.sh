#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SRC="$ROOT/src"
MAKEFILE="$ROOT/Makefile"
UI="$SRC/ZNUnifiedUI.mm"

test -f "$UI"
grep -q 'src/ZNUnifiedUI.mm' "$MAKEFILE"

MIGRATED='ZonoeRuntimeMenu.mm ZNDeferredBootstrap.mm ZNRuntimeMenuModalShell.mm ZNFeatureGroupUI.mm ZNFeatureRuntimeControlsV2.mm ZNPublicCompactUI.mm ZNFeatureBuilderUI.mm ZNFeatureBuilderControlsV2.mm ZNIL2CPPMethodFinderUI.mm ZNIL2CPPMethodFinderMenuBinding.mm ZNIL2CPPMethodFinderUXV2.mm ZNIL2CPPMethodFinderUIV3.mm ZNIL2CPPMethodFinderM2.mm ZNIL2CPPMethodFinderM21CancelUX.mm ZNIL2CPPMethodFinderM22StableCancelUX.mm ZNIL2CPPABIDetailUI.mm ZNRuntimeMethodCallFinderUI.mm ZNRuntimeMethodCallBuilderUI.mm ZNRuntimeMethodCallFeatureUI.mm ZNUXFixesV2.mm ZNMethodFinderM42UI.mm ZNMethodFinderM43UI.mm ZNMethodFinderM43Polish.mm ZNInstanceSelectionV2UI.mm ZNM441Hotfix.mm ZNM442SearchRestore.mm ZNM45AddressOwningMethodUI.mm ZNM46FullSignatureUI.mm ZNM461Polish.mm ZNM462CandidateBindingUI.mm ZNM47ReceiverCaptureUI.mm ZNM47MultiArgUI.mm ZNM47BuilderArgsUI.mm ZNM47VersionUI.mm ZNM49GenericInvokeEditableArgs.mm ZNMethodFinderUnifiedUI.mm ZNM51RuntimeArgControlsImmediateChain.mm ZNM51SilentCustomerExecution.mm ZNM52ChainExecuteButton.mm ZNM52MethodSearchHistory.mm ZNM53ControlBinding.mm ZNM55TypedControlBinding.mm ZNM551RuntimeSliderStability.mm ZNM562SliderIsolation.mm ZNM57RuntimeOnlyBuilderGate.mm ZNM57UnifiedRuntimeControls.mm ZNM584SchemeALayout.mm ZNM585UnifiedControlSemantics.mm ZNM585StaticRuntimeRange.mm ZNM58UnifiedControlRuntime.mm ZNM590UnifiedActionModel.mm ZNM591OffsetHookControls.mm ZNM600UnifiedFeatureSurface.mm ZNM630HardCutUI.mm ZNRangeControl.mm ZNM55StaticTypedBinding.mm ZNM56StaticValueCellBinding.mm'
for f in $MIGRATED; do
  test ! -e "$SRC/$f"
  ! grep -q "src/$f" "$MAKEFILE"
  grep -q "BEGIN $f" "$UI"
done

# UI ownership/behavior contracts that must remain present after flattening.
grep -q 'ZNRuntimeMenuControllerV040' "$UI"
grep -q 'renderPage' "$UI"
grep -q 'renderFullPage' "$UI"
grep -q 'renderCompactPage' "$UI"
grep -q '方法查找' "$UI"
grep -q 'IL2CPP Native Hook' "$UI"
grep -q '生成新二进制' "$UI"
grep -q 'Hook 测试' "$UI"
grep -q 'Direct Native Call：当前分支尚未接入 backend' "$UI"
grep -q 'method_exchangeImplementations' "$UI"
grep -q 'ZNRMCBuilderFinalizeBuildGate' "$UI"
grep -q 'ZNBuildCapabilityRegistry.h' "$UI"
grep -q 'ZNBinaryBuildCoordinator sharedCoordinator' "$UI"
test -f "$SRC/ZNBuildCapabilityRegistry.h"
test -f "$SRC/ZNBuildCapabilityRegistry.mm"
grep -q 'src/ZNBuildCapabilityRegistry.mm' "$MAKEFILE"
grep -q 'registerProviderIdentifier' "$SRC/ZNBuildCapabilityRegistry.mm"
grep -q 'ZNRegisterBuildCapabilityProvider' "$SRC/ZNBuildCapabilityRegistry.h"
grep -q 'runtime-method-call' "$SRC/ZNBuildCapabilityRegistry.mm"
grep -q 'native-hook' "$SRC/ZNBuildCapabilityRegistry.mm"
grep -q 'static-patch' "$SRC/ZNBuildCapabilityRegistry.mm"

# UI may ask only the coordinator whether Build is enabled. Concrete build
# provider stores must not participate in any build-enabled expression.
! grep -E 'build\.enabled.*filledCount|build\.enabled.*runtime|build\.enabled.*native|button\.enabled.*filledCount' "$UI"
grep -q 'znm630_hardCutRenderRuntimeAtY' "$UI"

# M6.8.4 BuildManifest / legacy isolation contract.
test -f "$SRC/ZNBuildItem.h"
test -f "$SRC/ZNBuildItem.mm"
test -f "$SRC/ZNBuildManifest.h"
test -f "$SRC/ZNBuildManifest.mm"
test -f "$SRC/ZNBuildExecutor.h"
test -f "$SRC/ZNBuildExecutor.mm"
test -f "$SRC/ZNBuildStaticPrepare.h"
test -f "$SRC/ZNBuildStaticPrepare.mm"
test -f "$SRC/legacy/ZNLegacyStaticBinaryPipeline.mm"
test ! -e "$SRC/ZNStaticBinaryPipeline.mm"
grep -q 'src/ZNBuildManifest.mm' "$MAKEFILE"
grep -q 'src/ZNBuildExecutor.mm' "$MAKEFILE"
grep -q 'src/ZNBuildStaticPrepare.mm' "$MAKEFILE"
grep -q 'src/legacy/ZNLegacyStaticBinaryPipeline.mm' "$MAKEFILE"
grep -q 'ZNBuildExecutorBuildWorkspace' "$UI"
! grep -q '\[ZNStaticBinaryBuilder buildWorkspace:ws' "$UI"
grep -q 'ZNLegacyM585PrepareStaticBuild' "$UI"
grep -q 'ZNLegacyM591PrepareStaticBuild' "$UI"
grep -q '\[legacy-isolated\]' "$UI"
! grep -q 'ZNLegacyM585PrepareStaticBuild' "$SRC/ZNBuildManifest.mm"
! grep -q 'ZNLegacyM591PrepareStaticBuild' "$SRC/ZNBuildManifest.mm"
grep -q 'ZNBuildPrepareStaticWorkspaceV1' "$SRC/ZNBuildManifest.mm"
grep -q 'legacy M585/M591 build prepare bypassed' "$SRC/ZNBuildStaticPrepare.mm"
! grep -q 'if(meta&&b1&&b2)method_exchangeImplementations(b1,b2);' "$UI"
grep -q 'ZNBuildManifest manifestForWorkspace' "$SRC/ZNBuildCapabilityRegistry.mm"
grep -q 'buildSnapshotForRowIndexes' "$SRC/ZNBuildExecutor.mm"
grep -q 'ZNRegisterBuildItemProvider' "$SRC/ZNBuildManifest.h"
grep -q 'runtimeMethodProvider.identifier=@"runtime-method-call"' "$SRC/ZNBuildManifest.mm"
grep -q 'nativeHookProvider.identifier=@"native-hook"' "$SRC/ZNBuildManifest.mm"
grep -q 'emitGroup=@"runtime-action-table"' "$SRC/ZNBuildManifest.mm"
grep -q 'emittedGroups' "$SRC/ZNBuildManifest.mm"
! grep -q 'runtimeProvider.identifier=@"runtime-actions"' "$SRC/ZNBuildManifest.mm"

# M6.8.4 Generated Data Layout V1 is the only supported newly-generated layout.
test -f "$SRC/ZNGeneratedDataLayout.h"
grep -q 'ZN44_STATIC_HEADER_FLAG_GENERATED_LAYOUT_V1' "$SRC/ZNStaticPatchFormat.h"
grep -q 'ZNGeneratedDataLayoutV1LocateRuntimeAction' "$SRC/ZNRuntimeActionBuilder.mm"
grep -q 'ZNGeneratedDataLayoutV1LocateRuntimeAction' "$SRC/ZNRuntimeActionSignaturePostprocess.mm"
grep -q 'ZNGeneratedDataLayoutV1LocateRuntimeAction' "$SRC/ZNRuntimeActionRuntime.mm"
grep -q 'ZNGeneratedDataLayoutV1LocateRuntimeAction' "$SRC/ZNNativeHookRuntime.mm"
grep -q 'ZNGeneratedDataLayoutV1LocateRuntimeAction' "$SRC/ZNM462RuntimeOnlyVerifier.mm"
grep -q 'return-bool-override' "$SRC/ZNM462RuntimeOnlyVerifier.mm"
grep -q 'struct-field-transform' "$SRC/ZNM462RuntimeOnlyVerifier.mm"
! grep -q 'section+staticBytes' "$SRC/ZNRuntimeActionRuntime.mm"
! grep -q 'section+staticBytes' "$SRC/ZNNativeHookRuntime.mm"

# M6.8.5 Runtime Capability Snapshot contract.
test -f "$SRC/ZNRuntimeCapabilityCoordinator.h"
test -f "$SRC/ZNRuntimeCapabilityCoordinator.mm"
grep -q 'src/ZNRuntimeCapabilityCoordinator.mm' "$MAKEFILE"
grep -q 'ZNRuntimeCapabilitySnapshot' "$SRC/ZNRuntimeCapabilityCoordinator.h"
grep -q 'ZNRuntimeCapabilityCoordinator' "$SRC/ZNRuntimeCapabilityCoordinator.h"
grep -q 'coordinator started; UI is snapshot-only' "$SRC/ZNRuntimeCapabilityCoordinator.mm"
grep -q 'currentSnapshot.runtimeMethods' "$UI"
grep -q 'currentSnapshot.nativeHooks' "$UI"
grep -q 'currentSnapshot' "$SRC/ZNFeatureSnapshotProvider.mm"
grep -q 'snapshot.staticRecords' "$SRC/ZNFeatureSnapshotProvider.mm"
! grep -q 'refreshGeneratedActions' "$UI"
! grep -q 'auto-install' "$UI"
grep -q 'if(self.hasScanned&&self.cachedImageCount==imageCount)return;uint64_t fingerprint' "$SRC/ZNRuntimeActionRuntime.mm"
grep -q 'if(self.generatedScanned&&self.generatedImageCount==count)return;' "$SRC/ZNNativeHookRuntime.mm"
grep -q 'snapshotStorage.imageCount==imageCount' "$SRC/ZNRuntimeCapabilityCoordinator.mm"

# M6.8.6 Permanent Native Hook Lifecycle contract.
test -f "$SRC/ZNNativeHookScheduler.h"
test -f "$SRC/ZNNativeHookScheduler.mm"
grep -q 'src/ZNNativeHookScheduler.mm' "$MAKEFILE"
grep -q 'Permanent Hook Lifecycle' "$SRC/ZNNativeHookScheduler.h"
grep -q 'com.zonoe.native-hook.scheduler' "$SRC/ZNNativeHookScheduler.mm"
grep -q 'RetryPending must not wait for the old' "$SRC/ZNNativeHookScheduler.mm"
test -f "$SRC/ZNNativeHookLifecycleBootstrap.h"
test -f "$SRC/ZNNativeHookLifecycleBootstrap.mm"
grep -q 'src/ZNNativeHookLifecycleBootstrap.mm' "$MAKEFILE"
grep -q 'ZNNativeHookEarlyLifecycleBootstrap' "$SRC/ZNNativeHookLifecycleBootstrap.mm"
grep -q '_dyld_register_func_for_add_image(ZNNativeHookLifecycleImageAdded)' "$SRC/ZNNativeHookLifecycleBootstrap.mm"
grep -q 'reconcileActions:actions' "$SRC/ZNNativeHookLifecycleBootstrap.mm"
! grep -q 'ZNNativeHookScheduler' "$SRC/ZNRuntimeCapabilityCoordinator.mm"
! grep -q 'restorePersistedNativeHooks' "$SRC/ZNRuntimeCapabilityCoordinator.mm"
grep -q 'ZNNativeHookScheduler sharedScheduler.*setDesiredValue' "$UI"
! grep -q 'ZNNativeHookRuntime sharedRuntime.*setValue:.*forAction:hook' "$UI"
! grep -q 'if(value==0)return \[self removeAction:action' "$SRC/ZNNativeHookRuntime.mm"
grep -q 'slot->enabled.load' "$SRC/ZNNativeHookRuntime.mm"
grep -q 'ZNReturnBoolOriginalFn' "$SRC/ZNNativeHookRuntime.mm"
grep -q 'ZNManagedCallbackOriginalFn' "$SRC/ZNNativeHookRuntime.mm"
grep -q 'ZNNativeHookRegistryEntry' "$SRC/ZNNativeHookRuntime.mm"
grep -q 'ZNNativeHookRegistryBind' "$SRC/ZNNativeHookRuntime.mm"
grep -q 'ZNNativeHookRegistryFind(action.actionID)' "$SRC/ZNNativeHookRuntime.mm"
grep -q 'ZNNativeHookRegistryUnbind(action.actionID)' "$SRC/ZNNativeHookRuntime.mm"
! grep -q 'ZNNativeResolveDescriptor(action.assembly.*removeAction' "$SRC/ZNNativeHookRuntime.mm"

# M6.9 Prepared Native Hook Descriptor contract.
test -f "$SRC/ZNNativeHookBuildPrepare.h"
test -f "$SRC/ZNNativeHookBuildPrepare.mm"
grep -q 'src/ZNNativeHookBuildPrepare.mm' "$MAKEFILE"
grep -q 'ZNBuildPrepareNativeHookDescriptorsV1' "$SRC/ZNBuildManifest.mm"
grep -Eq 'resolutionMode":@"(prepared-rva|static-prepatch-v1)"' "$SRC/ZNRuntimeActionBuilder.mm"
grep -q 'preparedRVA' "$SRC/ZNNativeHookAction.h"
grep -q 'ZNNativePreparedTargetForAction' "$SRC/ZNNativeHookRuntime.mm"
grep -q '缺少 M6.9 Prepared Descriptor' "$SRC/ZNNativeHookRuntime.mm"
python3 - "$SRC/ZNNativeHookRuntime.mm" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
start=s.index("- (BOOL)installAction:(ZNNativeHookAction *)action value:")
end=s.find("// Permanent lifecycle:", start)
if end < 0:
    end=s.find("// M6.8.6 permanent lifecycle", start)
assert end > start
formal=s[start:end]
assert "ZNNativePreparedTargetForAction" in formal
assert "ZNNativeResolveDescriptor" not in formal
assert "installTemporaryReturnBoolOverrideForCandidate" not in formal
assert "installTemporaryManagedCallbackShortCircuitForCandidate" not in formal
assert "installTemporaryStructFieldTransformForCandidate" not in formal
PY

# M6.10 Static Prepared Native Hook Backend contract.
test -f "$SRC/ZNNativeHookStaticPrepatch.h"
test -f "$SRC/ZNNativeHookStaticPrepatch.mm"
grep -q 'src/ZNNativeHookStaticPrepatch.mm' "$MAKEFILE"
grep -q 'ZNBuildInstallStaticPreparedNativeHooksV1' "$SRC/ZNBuildManifest.mm"
grep -q 'resolutionMode":@"static-prepatch-v1"' "$SRC/ZNRuntimeActionBuilder.mm"
grep -q 'staticHookSlotRVA' "$SRC/ZNNativeHookAction.h"
grep -q 'ZNNativeStaticPrepatchBind' "$SRC/ZNNativeHookRuntime.mm"
grep -q '__atomic_store_n' "$SRC/ZNNativeHookRuntime.mm"
grep -q 'ZNM610RelocationSafeFirstInstruction' "$SRC/ZNNativeHookStaticPrepatch.mm"
grep -q 'ZNM610BranchImm26' "$SRC/ZNNativeHookStaticPrepatch.mm"
grep -q 'ZNAdhocResignMachOAtPath' "$SRC/ZNNativeHookStaticPrepatch.mm"
python3 - "$SRC/ZNNativeHookRuntime.mm" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
start=s.index("- (BOOL)installAction:(ZNNativeHookAction *)action value:")
end=s.index("// Permanent lifecycle:", start)
formal=s[start:end]
assert "ZNNativeStaticPrepatchBind" not in formal or "zn_installPrepared" in formal
assert "installResolvedTarget" not in formal
assert "ZNNativeHookBackend sharedBackend" not in formal
assert "DobbyHook" not in formal
assert "ZNNativeResolveDescriptor" not in formal
PY
grep -q 'if(action.staticPrepatch)' "$SRC/ZNNativeHookRuntime.mm"
grep -q 'ZNNativeStaticPrepatchClear' "$SRC/ZNNativeHookRuntime.mm"

echo "single UI owner + M6.8.6 Lifecycle + M6.9 Prepared Descriptor + M6.10 Static Prepatch contract: OK"
