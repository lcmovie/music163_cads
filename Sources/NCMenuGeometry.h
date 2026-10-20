#ifndef NC_MENU_GEOMETRY_H
#define NC_MENU_GEOMETRY_H
typedef struct {
    double rowY;
    double shift;
    double accountY;
    double contentHeight;
} NCMenuGeometry;
int NCMenuGeometryCompute(double accountCurrentY, double previousShift, double rowHeight,
                          double gap, double originalContentHeight, NCMenuGeometry *out);
#endif
