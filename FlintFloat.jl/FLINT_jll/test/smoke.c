/* Compile against the bundled artifact headers and the matching dependency headers. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <flint/arb.h>
#include <flint/acb.h>
#include <flint/dfloat.h>
#include <flint/nfloat.h>
#include <flint/gr.h>

int main(void)
{
    assert(strcmp(flint_version, "3.7.0-dev") == 0);
    assert(dfloat_is_supported());
    d2_t dx, dy, dz;
    d2_set_d(dx, 2.0);
    d2_set_d(dy, 3.0);
    d2_add(dz, dx, dy);
    assert(d2_get_d(dz) == 5.0);

    gr_ctx_t ctx;
    assert(nfloat_ctx_init(ctx, 128, 0) == GR_SUCCESS);
    gr_ptr nx = gr_heap_init(ctx);
    gr_ptr ny = gr_heap_init(ctx);
    gr_ptr nz = gr_heap_init(ctx);
    assert(nfloat_set_d(nx, 2.0, ctx) == GR_SUCCESS);
    assert(nfloat_set_d(ny, 3.0, ctx) == GR_SUCCESS);
    assert(nfloat_add(nz, nx, ny, ctx) == GR_SUCCESS);
    arf_t result;
    arf_init(result);
    assert(nfloat_get_arf(result, nz, ctx) == GR_SUCCESS);
    assert(arf_get_d(result, ARF_RND_NEAR) == 5.0);
    arf_clear(result);
    gr_heap_clear(nx, ctx);
    gr_heap_clear(ny, ctx);
    gr_heap_clear(nz, ctx);
    gr_ctx_clear(ctx);

    arb_t ax, ay, az;
    arb_init(ax); arb_init(ay); arb_init(az);
    arb_set_si(ax, 2); arb_set_si(ay, 3);
    arb_add(az, ax, ay, 128);
    assert(arb_contains_si(az, 5));
    arb_clear(ax); arb_clear(ay); arb_clear(az);

    acb_t cx, cz;
    acb_init(cx); acb_init(cz);
    acb_one(cx);
    acb_add(cz, cx, cx, 128);
    acb_sub(cz, cz, cx, 128);
    assert(acb_is_one(cz));
    acb_clear(cx); acb_clear(cz);
    printf("FLINT %s: dfloat, nfloat, arb, acb arithmetic passed\n", flint_version);
    printf("ABI sizes: d2=%zu arf=%zu mag=%zu arb=%zu acb=%zu gr_ctx=%zu\n",
           sizeof(d2_struct), sizeof(arf_struct), sizeof(mag_struct),
           sizeof(arb_struct), sizeof(acb_struct), sizeof(gr_ctx_struct));
    return 0;
}
