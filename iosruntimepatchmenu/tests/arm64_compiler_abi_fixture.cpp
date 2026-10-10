#include <cassert>
#include <cstdint>
#include <cstdio>
#include <type_traits>

struct Pair64 { uint64_t lo, hi; };
struct Triple64 { uint64_t a, b, c; };
struct HFA4 { float a, b, c, d; };
struct HFA2D { double a, b; };
struct Align16 { alignas(16) uint64_t a, b; };

static_assert(sizeof(Pair64)==16 && sizeof(Triple64)==24, "aggregate sizes");
static_assert(sizeof(HFA4)==16 && sizeof(HFA2D)==16, "HFA sizes");
static_assert(alignof(Align16)==16, "alignment");

#if !defined(__aarch64__) && !defined(__arm64__)
#error "This compiler-ABI test requires an arm64 runner"
#endif

#if defined(__clang__)
#define NOINLINE __attribute__((noinline,optnone))
#else
#define NOINLINE __attribute__((noinline))
#endif

extern "C" NOINLINE uint64_t pair_call(Pair64 x) {
    return x.lo ^ (x.hi << 1);
}
extern "C" NOINLINE uint64_t indirect_call(Triple64 x) {
    return x.a + 3*x.b + 7*x.c;
}
extern "C" NOINLINE float hfa_call(HFA4 x) {
    return x.a + 2*x.b + 3*x.c + 4*x.d;
}
extern "C" NOINLINE double hfad_call(HFA2D x) {
    return x.a + 2*x.b;
}
extern "C" NOINLINE uint64_t gpr_overflow(
    uint64_t a,uint64_t b,uint64_t c,uint64_t d,
    uint64_t e,uint64_t f,uint64_t g,Pair64 x,uint64_t tail) {
    return a+b+c+d+e+f+g+x.lo+2*x.hi+tail;
}
extern "C" NOINLINE float fpr_overflow(
    double a,double b,double c,double d,double e,double f,HFA4 x,double tail) {
    return float(a+b+c+d+e+f+tail)+hfa_call(x);
}
extern "C" NOINLINE uint64_t aligned_stack(
    uint64_t a,uint64_t b,uint64_t c,uint64_t d,
    uint64_t e,uint64_t f,uint64_t g,uint64_t h,
    Pair64 first,Align16 second) {
    return a+b+c+d+e+f+g+h+first.lo+first.hi+second.a+second.b;
}

int main() {
    // Calls cross a non-inlined C ABI boundary; arguments are checked in callee.
    assert(pair_call({17,23})==(17ULL^(23ULL<<1)));
    assert(indirect_call({2,3,5})==46ULL);
    assert(hfa_call({1,2,3,4})==30.0f);
    assert(hfad_call({2,3})==8.0);
    assert(gpr_overflow(1,2,3,4,5,6,7,{11,13},17)==82ULL);
    assert(fpr_overflow(1,2,3,4,5,6,{1,2,3,4},7)==58.0f);
    assert(aligned_stack(1,2,3,4,5,6,7,8,{9,10},{11,12})==78ULL);
    std::puts("arm64_compiler_abi_fixture: PASS");
}
