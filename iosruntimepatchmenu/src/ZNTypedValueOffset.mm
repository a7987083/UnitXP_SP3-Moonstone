#import "ZNTypedValueOffset.h"
#import "ZNH5GGValueBackend.h"
#import "ZNPatchCore.h"

static NSString *ZNTVTrim(NSString *s) {
    return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNTVParseRVA(NSString *text, uint64_t *out, NSString **error) {
    NSString *s = ZNTVTrim(text);
    NSString *lower = s.lowercaseString;
    for (NSString *prefix in @[@"va:", @"runtime:", @"file:", @"address:", @"addr:", @"location:"]) {
        if ([lower hasPrefix:prefix]) {
            if (error) *error = @"Only image-relative RVA is accepted";
            return NO;
        }
    }
    if (![lower hasPrefix:@"0x"] || s.length <= 2) {
        if (error) *error = @"RVA must use 0x... hexadecimal format";
        return NO;
    }
    NSScanner *scanner = [NSScanner scannerWithString:[s substringFromIndex:2]];
    unsigned long long value = 0;
    if (![scanner scanHexLongLong:&value] || !scanner.isAtEnd) {
        if (error) *error = @"Invalid RVA";
        return NO;
    }
    if (out) *out = (uint64_t)value;
    return YES;
}

static BOOL ZNTVParseNumericValue(NSString *value, NSString *type, double *out, NSString **error) {
    NSString *s = ZNTVTrim(value);
    if (!s.length) {
        if (error) *error = @"Value is empty";
        return NO;
    }
    char *end = NULL;
    double parsed = strtod(s.UTF8String, &end);
    if (!end || end == s.UTF8String || *end != '\0' || !isfinite(parsed)) {
        if (error) *error = [NSString stringWithFormat:@"Invalid %@ value", type ?: @""];
        return NO;
    }
    if (out) *out = parsed;
    return YES;
}

@implementation ZNTypedValueOffset {
    NSString *_originalValueText;
    uint64_t _rva;
    uint64_t _resolvedAddress;
    BOOL _validated;
    BOOL _applied;
    NSString *_lastError;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _title = @"Value Offset";
    _target = @"main";
    _offsetText = @"";
    _valueType = @"F32";
    _controlKind = ZNTypedValueControlKindSlider;
    _valueText = @"0";
    _minValue = 0.0;
    _maxValue = 100.0;
    _stepValue = 1.0;
    _originalValueText = @"";
    _lastError = @"";
    return self;
}

- (NSString *)originalValueText { return _originalValueText ?: @""; }
- (uint64_t)rva { return _rva; }
- (uint64_t)resolvedAddress { return _resolvedAddress; }
- (BOOL)isValidated { return _validated; }
- (BOOL)isApplied { return _applied; }
- (NSString *)lastError { return _lastError ?: @""; }

- (BOOL)validate:(NSString **)error {
    _validated = NO;
    _resolvedAddress = 0;
    _originalValueText = @"";
    _lastError = @"";

    NSString *target = ZNTVTrim(self.target);
    if (!target.length) target = @"main";
    NSString *type = self.valueType.uppercaseString ?: @"";
    if (![ZNH5GGValueBackend isSupportedType:type]) {
        _lastError = [NSString stringWithFormat:@"Unsupported value type: %@", self.valueType ?: @""];
        if (error) *error = _lastError;
        return NO;
    }

    if (self.controlKind == ZNTypedValueControlKindSlider) {
        if (!isfinite(self.minValue) || !isfinite(self.maxValue) || self.minValue > self.maxValue) {
            _lastError = @"Slider range is invalid";
            if (error) *error = _lastError;
            return NO;
        }
        if (!isfinite(self.stepValue) || self.stepValue <= 0) {
            _lastError = @"Slider step must be greater than zero";
            if (error) *error = _lastError;
            return NO;
        }
    }

    uint64_t rva = 0;
    NSString *local = nil;
    if (!ZNTVParseRVA(self.offsetText, &rva, &local)) {
        _lastError = local ?: @"Invalid RVA";
        if (error) *error = _lastError;
        return NO;
    }

    ZNModuleManager *modules = [ZNModuleManager sharedManager];
    if (![modules moduleNamed:target]) {
        _lastError = [NSString stringWithFormat:@"Target image not loaded: %@", target];
        if (error) *error = _lastError;
        return NO;
    }
    uint64_t address = (uint64_t)[modules runtimeAddressForModule:target rva:rva];
    if (!address) {
        _lastError = [NSString stringWithFormat:@"Cannot resolve %@ + 0x%llX", target, rva];
        if (error) *error = _lastError;
        return NO;
    }

    ZNH5GGValueBackend *backend = [ZNH5GGValueBackend sharedBackend];
    if (!backend.available) {
        _lastError = backend.availabilityText;
        if (error) *error = _lastError;
        return NO;
    }
    NSString *original = [backend readAddress:address type:type error:&local];
    if (!original.length) {
        _lastError = local ?: @"Unable to preview typed value";
        if (error) *error = _lastError;
        return NO;
    }

    self.target = target;
    self.valueType = type;
    self.offsetText = [NSString stringWithFormat:@"0x%llX", rva];
    _rva = rva;
    _resolvedAddress = address;
    _originalValueText = original;
    _validated = YES;
    return YES;
}

- (BOOL)applyValue:(NSString *)value error:(NSString **)error {
    NSString *local = nil;
    if (!_validated && ![self validate:&local]) {
        _lastError = local ?: @"Typed value offset is not validated";
        if (error) *error = _lastError;
        return NO;
    }

    double numeric = 0;
    if (!ZNTVParseNumericValue(value, self.valueType, &numeric, &local)) {
        _lastError = local ?: @"Invalid value";
        if (error) *error = _lastError;
        return NO;
    }
    if (self.controlKind == ZNTypedValueControlKindSlider && (numeric < self.minValue || numeric > self.maxValue)) {
        _lastError = [NSString stringWithFormat:@"Value %.10g is outside slider range %.10g...%.10g", numeric, self.minValue, self.maxValue];
        if (error) *error = _lastError;
        return NO;
    }

    ZNH5GGValueBackend *backend = [ZNH5GGValueBackend sharedBackend];
    if (![backend writeAddress:_resolvedAddress value:ZNTVTrim(value) type:self.valueType error:&local]) {
        _lastError = local ?: @"Typed value write failed";
        if (error) *error = _lastError;
        return NO;
    }

    self.valueText = ZNTVTrim(value);
    _applied = YES;
    _lastError = @"";
    return YES;
}

- (BOOL)restore:(NSString **)error {
    if (!_applied) return YES;
    if (!_validated || !_resolvedAddress || !_originalValueText.length) {
        _lastError = @"Original value is unavailable";
        if (error) *error = _lastError;
        return NO;
    }
    NSString *local = nil;
    if (![[ZNH5GGValueBackend sharedBackend] writeAddress:_resolvedAddress value:_originalValueText type:self.valueType error:&local]) {
        _lastError = local ?: @"Restore original value failed";
        if (error) *error = _lastError;
        return NO;
    }
    self.valueText = _originalValueText;
    _applied = NO;
    _lastError = @"";
    return YES;
}

@end
