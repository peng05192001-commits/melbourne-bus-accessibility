# PyQGIS script for the QGIS 3.44 Python console.
# Builds the service, proximity and residential-distance maps as PNG layouts.
# Input: data/processed/accessibility.gpkg, exported by export_map_layers.sh.
from pathlib import Path
import os
from qgis.core import (
    QgsProject, QgsVectorLayer, QgsCoordinateReferenceSystem, QgsCoordinateTransform,
    QgsFillSymbol, QgsSingleSymbolRenderer, QgsHeatmapRenderer, QgsGradientColorRamp,
    QgsGradientStop, QgsColorRampLegendNodeSettings, QgsCategorizedSymbolRenderer,
    QgsRendererCategory, QgsGraduatedSymbolRenderer, QgsRendererRange, QgsPalLayerSettings,
    QgsTextFormat, QgsTextBufferSettings, QgsVectorLayerSimpleLabeling, QgsPrintLayout,
    QgsLayoutItemLabel, QgsLayoutItemMap, QgsLayoutItemLegend, QgsLayoutItemScaleBar,
    QgsLayoutItemPicture, QgsLayoutPoint, QgsLayoutSize, QgsLayoutExporter, QgsLayerTree,
    QgsLegendStyle, Qgis)
from qgis.PyQt.QtGui import QColor, QFont

ROOT = Path(__file__).resolve().parents[1]
D = str(ROOT / 'assets')
G = str(ROOT / 'data' / 'processed' / 'accessibility.gpkg')
P = QgsProject.instance()
P.clear()
P.setCrs(QgsCoordinateReferenceSystem('EPSG:7855'))      # GDA2020 / MGA zone 55
P.setTitle('Melbourne bus accessibility')


def vl(name, label):
    layer = QgsVectorLayer(f'{G}|layername={name}', label, 'ogr')
    assert layer.isValid(), name
    P.addMapLayer(layer)
    return layer


lga = vl('lga_res_access', 'LGA boundary')
mb = vl('res_mb_access', 'Residential mesh blocks')
st = vl('bus_stops', 'Bus stops')
out = vl('gmel_outline', 'Greater Melbourne')
lgaC = vl('lga_res_access', 'Residential MBs within 400 m|(straight line) of a bus stop (%)')

# Styles: boundaries
lga.setRenderer(QgsSingleSymbolRenderer(QgsFillSymbol.createSimple(
    {'color': '0,0,0,0', 'outline_color': '90,90,90', 'outline_width': '0.25'})))
out.setRenderer(QgsSingleSymbolRenderer(QgsFillSymbol.createSimple(
    {'color': '0,0,0,0', 'outline_color': '30,30,30', 'outline_width': '0.6'})))

# Figure 1: heatmap of stops weighted by scheduled weekday stop departures
hm = QgsHeatmapRenderer()
hm.setWeightExpression('"departures"')
hm.setRadius(1500)
hm.setRadiusUnit(Qgis.RenderUnit.MapUnits)
stops = [QgsGradientStop(0.08, QColor(255, 237, 160, 150)),
         QgsGradientStop(0.3, QColor(254, 178, 76, 220)),
         QgsGradientStop(0.6, QColor(240, 59, 32)),
         QgsGradientStop(0.85, QColor(189, 0, 38))]
hm.setColorRamp(QgsGradientColorRamp(QColor(255, 255, 255, 0), QColor(128, 0, 38), False, stops))
hm.setRenderQuality(1)
ls = QgsColorRampLegendNodeSettings()
ls.setMinimumLabel('Low')
ls.setMaximumLabel('High')
hm.setLegendSettings(ls)
st.setRenderer(hm)
st.setOpacity(0.85)
st.setName('Scheduled weekday stop departures (heatmap)')

# Figure 4: residential MBs by straight-line distance band to the nearest stop
cats = [(1, '0-200 m', '#1a9850'), (2, '200-400 m', '#a6d96a'),
        (3, '400-800 m', '#fdae61'), (4, 'over 800 m (gap)', '#d7191c')]
mb.setRenderer(QgsCategorizedSymbolRenderer('walk_band', [
    QgsRendererCategory(v, QgsFillSymbol.createSimple({'color': c, 'outline_style': 'no'}), t)
    for v, t, c in cats]))
mb.setName('Straight-line distance to nearest bus stop')

# Figure 2: LGA choropleth of 400 m straight-line coverage
ranges = [(0, 60, '< 60%', '#d7191c'), (60, 75, '60-75%', '#fdae61'),
          (75, 85, '75-85%', '#ffffbf'), (85, 90, '85-90%', '#a6d96a'),
          (90, 100, '90-100%', '#1a9641')]
lgaC.setRenderer(QgsGraduatedSymbolRenderer('pct_mb_400m', [
    QgsRendererRange(a, b, QgsFillSymbol.createSimple(
        {'color': c, 'outline_color': '80,80,80', 'outline_width': '0.25'}), t)
    for a, b, t, c in ranges]))
pal = QgsPalLayerSettings()
pal.fieldName = "regexp_replace(\"lga_name\", ' \\\\(Vic\\\\.\\\\)', '')"
pal.isExpression = True
tf = QgsTextFormat()
tf.setFont(QFont('Arial'))
tf.setSize(6.5)
buf = QgsTextBufferSettings()
buf.setEnabled(True)
buf.setSize(0.8)
tf.setBuffer(buf)
pal.setFormat(tf)
lgaC.setLabeling(QgsVectorLayerSimpleLabeling(pal))
lgaC.setLabelsEnabled(True)

to_mga = QgsCoordinateTransform(QgsCoordinateReferenceSystem('EPSG:7844'), P.crs(), P)
ext = to_mga.transformBoundingBox(out.extent())
ext.grow(3000)
SOURCE = ('Data: PTV GTFS feed (selected weekday: Wed 21 Jun 2023); ABS ASGS Ed. 3 '
          'Mesh Blocks and allocation files (2021).\nCRS: GDA2020 / MGA zone 55 (EPSG:7855).')


def label(L, text, size, x, y, w, h, bold=False):
    item = QgsLayoutItemLabel(L)
    item.setText(text)
    item.setFont(QFont('Arial', size, QFont.Bold if bold else QFont.Normal))
    item.attemptMove(QgsLayoutPoint(x, y))
    item.attemptResize(QgsLayoutSize(w, h))
    L.addLayoutItem(item)


def layout(name, title, sub, layers, legend_layers, png):
    manager = P.layoutManager()
    old = manager.layoutByName(name)
    if old:
        manager.removeLayout(old)
    L = QgsPrintLayout(P)
    L.initializeDefaults()
    L.setName(name)
    manager.addLayout(L)
    L.pageCollection().page(0).setPageSize(QgsLayoutSize(297, 210))
    label(L, title, 16, 8, 5, 280, 9, bold=True)
    label(L, sub, 9, 8, 14, 280, 6)
    mp = QgsLayoutItemMap(L)
    mp.attemptMove(QgsLayoutPoint(8, 21))
    mp.attemptResize(QgsLayoutSize(205, 180))
    mp.setCrs(P.crs())
    mp.setLayers(layers)
    mp.setKeepLayerSet(True)
    mp.zoomToExtent(ext)
    mp.setFrameEnabled(True)
    L.addLayoutItem(mp)
    lg = QgsLayoutItemLegend(L)
    lg.setLinkedMap(mp)
    lg.setAutoUpdateModel(False)
    lg.setTitle('Legend')
    root = QgsLayerTree()
    for layer in legend_layers:
        root.addLayer(layer)
    lg.model().setRootGroup(root)
    lg.setWrapString('|')
    lg.setStyleFont(QgsLegendStyle.Title, QFont('Arial', 11, QFont.Bold))
    lg.setStyleFont(QgsLegendStyle.Subgroup, QFont('Arial', 9, QFont.Bold))
    lg.setStyleFont(QgsLegendStyle.SymbolLabel, QFont('Arial', 8))
    lg.attemptMove(QgsLayoutPoint(218, 24))
    L.addLayoutItem(lg)
    sb = QgsLayoutItemScaleBar(L)
    sb.setStyle('Single Box')
    sb.setLinkedMap(mp)
    sb.applyDefaultSize()
    sb.setUnits(Qgis.DistanceUnit.Kilometers)
    sb.setUnitLabel('km')
    sb.setNumberOfSegments(4)
    sb.setNumberOfSegmentsLeft(0)
    sb.setUnitsPerSegment(10)
    sbf = QgsTextFormat()
    sbf.setFont(QFont('Arial'))
    sbf.setSize(8)
    sb.setTextFormat(sbf)
    sb.attemptMove(QgsLayoutPoint(12, 188))
    L.addLayoutItem(sb)
    na = QgsLayoutItemPicture(L)
    na.setPicturePath(':/images/north_arrows/layout_default_north_arrow.svg')
    na.attemptMove(QgsLayoutPoint(198, 24))
    na.attemptResize(QgsLayoutSize(12, 16))
    L.addLayoutItem(na)
    label(L, SOURCE, 7, 218, 185, 75, 18)
    settings = QgsLayoutExporter.ImageExportSettings()
    settings.dpi = 220
    result = QgsLayoutExporter(L).exportToImage(os.path.join(D, png), settings)
    print(name, 'export result', result)        # 0 = success


layout('Map 1 Heatmap', "Where Melbourne's scheduled bus service is concentrated",
       'QGIS heatmap of 18,832 bus stops weighted by scheduled stop departures '
       '(selected weekday: Wed 21 June 2023), with LGA boundaries',
       [out, lga, st], [st, lga], 'service-intensity.png')
layout('Map 2 LGA coverage', 'Residential bus-stop proximity by LGA',
       'Share of residential mesh-block representative points within 400 m '
       '(straight line) of a bus stop',
       [out, lgaC], [lgaC], 'lga-proximity.png')
layout('Map 3 Gaps', 'Straight-line distance from residential mesh blocks to the nearest bus stop',
       'Residential mesh blocks (n = 46,608) coloured by the distance from their representative '
       'point (ST_PointOnSurface) to the nearest stop',
       [out, lga, mb], [mb, lga], 'residential-distance-bands.png')
P.write(os.path.join(D, 'melbourne-bus-accessibility.qgz'))
print('saved project')
