#include "NCMenuGeometry.h"
int NCMenuGeometryCompute(double accountCurrentY, double previousShift, double rowHeight,
                          double gap, double originalContentHeight, NCMenuGeometry *out) {
    if (!out || !(accountCurrentY >= -1000 && accountCurrentY < 1000000) ||
        !(previousShift >= 0 && previousShift < 500) || !(rowHeight >= 32 && rowHeight <= 96) ||
        !(gap >= 0 && gap <= 48) || !(originalContentHeight >= rowHeight && originalContentHeight < 1000000)) return 0;
    out->rowY = accountCurrentY - previousShift;
    out->shift = rowHeight + gap;
    out->accountY = out->rowY + out->shift;
    out->contentHeight = originalContentHeight + out->shift;
    return 1;
}
