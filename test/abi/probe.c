/* ABI probe: prints layout facts for every struct mirrored by FlintFloats.
 * Build: see test/abi/run.sh. Output is "key value" lines, one per fact. */
#include <stdio.h>
#include <stddef.h>
#include <stdalign.h>
#include <flint/flint.h>
#include <flint/arf.h>
#include <flint/acf.h>
#include <flint/arb.h>
#include <flint/acb.h>
#include <flint/mag.h>
#include <flint/dfloat.h>
#include <flint/nfloat.h>
#include <flint/gr.h>

#define SZ(name, T) printf("sizeof.%s %zu\nalign.%s %zu\n", name, sizeof(T), name, (size_t) alignof(T))
#define OFF(name, T, f) printf("offsetof.%s.%s %zu\n", name, #f, offsetof(T, f))

int main(void)
{
    printf("flint_version %s\n", flint_version);
    printf("sizeof.slong %zu\nsizeof.ulong %zu\nsizeof.mp_limb_t %zu\nsizeof.int %zu\nsizeof.long %zu\n",
           sizeof(slong), sizeof(ulong), sizeof(mp_limb_t), sizeof(int), sizeof(long));
    printf("slong_signed %d\nulong_signed %d\n", (slong) -1 < 0, (ulong) -1 < 0);
    printf("flint_bits %d\n", (int) FLINT_BITS);

    SZ("mag", mag_struct);
    OFF("mag", mag_struct, exp); OFF("mag", mag_struct, man);

    SZ("arf", arf_struct);
    OFF("arf", arf_struct, exp); OFF("arf", arf_struct, size);
    OFF("arf", arf_struct, d);

    SZ("acf", acf_struct);
    OFF("acf", acf_struct, real); OFF("acf", acf_struct, imag);

    SZ("arb", arb_struct);
    OFF("arb", arb_struct, mid); OFF("arb", arb_struct, rad);

    SZ("acb", acb_struct);
    OFF("acb", acb_struct, real); OFF("acb", acb_struct, imag);

    SZ("d1", d1_struct); SZ("d2", d2_struct); SZ("d3", d3_struct); SZ("d4", d4_struct);
    SZ("d1b", d1b_struct); SZ("d2b", d2b_struct); SZ("d3b", d3b_struct); SZ("d4b", d4b_struct);
    OFF("d2b", d2b_struct, d); OFF("d2b", d2b_struct, rad);
    OFF("d4b", d4b_struct, d); OFF("d4b", d4b_struct, rad);

    SZ("gr_ctx", gr_ctx_struct);
    printf("NFLOAT_HEADER_LIMBS %d\n", (int) NFLOAT_HEADER_LIMBS);
    printf("NFLOAT_MIN_LIMBS %d\nNFLOAT_MAX_LIMBS %d\n", (int) NFLOAT_MIN_LIMBS, (int) NFLOAT_MAX_LIMBS);
    printf("sizeof.nfloat_ctx_t %zu\n", sizeof(_nfloat_ctx_struct));
    printf("offsetof.nfloat_ctx.nlimbs %zu\noffsetof.nfloat_ctx.flags %zu\noffsetof.nfloat_ctx.rnd %zu\noffsetof.nfloat_ctx.func_prec %zu\n",
           offsetof(_nfloat_ctx_struct, nlimbs), offsetof(_nfloat_ctx_struct, flags),
           offsetof(_nfloat_ctx_struct, rnd), offsetof(_nfloat_ctx_struct, func_prec));
    printf("NFLOAT_ALLOW_UNDERFLOW %d\nNFLOAT_ALLOW_INF %d\nNFLOAT_ALLOW_NAN %d\n",
           NFLOAT_ALLOW_UNDERFLOW, NFLOAT_ALLOW_INF, NFLOAT_ALLOW_NAN);
    printf("NFLOAT_EXP_ZERO %ld\nNFLOAT_EXP_POS_INF %ld\nNFLOAT_EXP_NEG_INF %ld\nNFLOAT_EXP_NAN %ld\n",
           (long) NFLOAT_EXP_ZERO, (long) NFLOAT_EXP_POS_INF, (long) NFLOAT_EXP_NEG_INF, (long) NFLOAT_EXP_NAN);
    printf("sizeof.gr_status %zu\n", sizeof(int));
    printf("GR_SUCCESS %d\nGR_DOMAIN %d\nGR_UNABLE %d\nGR_TEST_FAIL %d\n",
           (int) GR_SUCCESS, (int) GR_DOMAIN, (int) GR_UNABLE, (int) GR_TEST_FAIL);
    printf("ARF_RND_DOWN %d\nARF_RND_UP %d\nARF_RND_FLOOR %d\nARF_RND_CEIL %d\nARF_RND_NEAR %d\n",
           (int) ARF_RND_DOWN, (int) ARF_RND_UP, (int) ARF_RND_FLOOR, (int) ARF_RND_CEIL, (int) ARF_RND_NEAR);
    return 0;
}
