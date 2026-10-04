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

echo "single UI owner contract: OK"
