#include "dbopl_wrapper.h"
#include "dbopl.h"

struct DBOPLChipImpl {
    Chip chip;
    bool tables_inited;
};

DBOPLChip* dbopl_create(int32_t sample_rate) {
    auto* c = new DBOPLChipImpl();
    c->tables_inited = false;

    // Init tables once per process is ideal; this is cheap enough for a CLI.
    DBOPL_InitTables();
    c->tables_inited = true;

    Chip__Chip(&c->chip);
    Chip__Setup(&c->chip, sample_rate);
    return reinterpret_cast<DBOPLChip*>(c);
}

void dbopl_destroy(DBOPLChip* chip) {
    delete reinterpret_cast<DBOPLChipImpl*>(chip);
}

void dbopl_write(DBOPLChip* chip, uint8_t reg, uint8_t value) {
    if (!chip) return;
    auto* c = reinterpret_cast<DBOPLChipImpl*>(chip);
    Chip__WriteReg(&c->chip, reg, value);
}

void dbopl_generate(DBOPLChip* chip, int32_t frames, int32_t* out_buffer) {
    if (!chip || !out_buffer || frames <= 0) return;
    auto* c = reinterpret_cast<DBOPLChipImpl*>(chip);
    Chip__GenerateBlock2(&c->chip, frames, out_buffer);
}
