# LGA proximity and scheduled-service comparison (matplotlib).
# Input: lga_res_access.csv, exported from ptv.lga_res_access by 05_export_lga_summary.sql.
from pathlib import Path
import csv
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

ROOT = Path(__file__).resolve().parents[1]
rows = list(csv.DictReader((ROOT / 'data' / 'lga_res_access.csv').open(encoding='utf-8')))
for r in rows:
    for k in ('est_residents', 'pct_mb_400m', 'departures_per_1000_res', 'weekday_departures'):
        r[k] = float(r[k])
total_dep = sum(r['weekday_departures'] for r in rows)
METRO_X = 81.0                                   # metro share of MBs within 400 m (Stage Q1)
METRO_Y = total_dep / 4917750 * 1000             # metro stop departures per 1,000 residents


def colour(p):
    if p >= 85:
        return '#1a9641'
    if p >= 75:
        return '#c9b52a'
    if p >= 60:
        return '#fdae61'
    return '#d7191c'


plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 9})
fig, ax = plt.subplots(figsize=(8.2, 5.2), dpi=220)
for r in rows:
    ax.scatter(r['pct_mb_400m'], r['departures_per_1000_res'], s=r['est_residents'] / 900,
               color=colour(r['pct_mb_400m']), alpha=0.75, edgecolor='#333', linewidth=0.5,
               zorder=3)
offsets = {'Manningham': (-62, 4), 'Yarra': (-30, -12), 'Boroondara': (-58, -4),
           'Macedon Ranges': (5, -10), 'Cardinia': (-40, -3), 'Mornington Peninsula': (8, -4),
           'Melton': (-12, 10), 'Casey': (14, -3), 'Glen Eira': (6, -10),
           'Wyndham': (-20, -16), 'Port Phillip': (-30, -15), 'Stonnington': (7, -9),
           'Hume': (-26, 8), 'Whitehorse': (6, 5), 'Maribyrnong': (-14, 9),
           'Moreland': (5, 3), 'Monash': (-40, 6)}
shown = set(offsets) | {'Melbourne', 'Murrindindi', 'Mitchell', 'Nillumbik'}
for r in rows:
    name = r['lga_name'].replace(' (Vic.)', '')
    if name in shown:
        ax.annotate(name, (r['pct_mb_400m'], r['departures_per_1000_res']),
                    xytext=offsets.get(name, (5, 3)), textcoords='offset points', fontsize=7.2)
ax.axvline(METRO_X, color='#777', ls='--', lw=0.8)
ax.axhline(METRO_Y, color='#777', ls='--', lw=0.8)
ax.text(METRO_X + 0.5, 8, 'Metro 81.0%', fontsize=7, color='#555')
ax.text(19, METRO_Y + 6, f'Metro {METRO_Y:.0f} per 1,000', fontsize=7, color='#555')
ax.set_xlabel('Residential MBs within 400 m (straight line) of a bus stop (%)')
ax.set_ylabel('Scheduled stop departures per 1,000 proxy residents')
ax.set_title('Proximity versus service intensity, 35 LGAs '
             '(bubble size = population proxy)', fontsize=10, loc='left', fontweight='bold')
handles = [Line2D([], [], marker='o', ls='', color=c, markersize=7, alpha=.8, label=t)
           for c, t in [('#1a9641', '85-100%'), ('#c9b52a', '75-85%'),
                        ('#fdae61', '60-75%'), ('#d7191c', '< 60%')]]
ax.legend(handles=handles, title='Proximity class', loc='upper left', fontsize=7.5,
          title_fontsize=8, frameon=False)
ax.set_xlim(18, 100)
ax.set_ylim(0, 410)
ax.grid(alpha=0.25, zorder=0)
for side in ('top', 'right'):
    ax.spines[side].set_visible(False)
plt.tight_layout()
plt.savefig(ROOT / 'assets' / 'proximity-versus-service.png')
print('saved proximity-versus-service.png', len(rows), 'LGAs, metro', round(METRO_Y, 1))
