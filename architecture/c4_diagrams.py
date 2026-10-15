"""Generate mcl-agora's C4 diagrams: assets/c4-context.svg, assets/c4-containers.svg
and assets/c4-components.svg.

Run:  python3 architecture/c4_diagrams.py

The style block is the house one (mcl-fovea's): plain classes with literal
colours and a prefers-color-scheme: dark block, and no CSS custom properties,
because rsvg-convert renders those black. After a change, render each one
(rsvg-convert -w 1400 assets/c4-context.svg -o /tmp/c.png) and look at it;
keep architecture/README.md's tables in step.
"""
import os
from xml.sax.saxutils import escape

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

SANS = '"Atkinson Hyperlegible", "Segoe UI", system-ui, -apple-system, Helvetica, Arial, sans-serif'
MONO = '"JetBrains Mono", ui-monospace, Menlo, Consolas, monospace'

STYLE = f"""<style>
.t-name {{ font-family: {SANS}; font-size: 15px; font-weight: 700; }}
.t-desc {{ font-family: {SANS}; font-size: 12.5px; }}
.t-rel {{ font-family: {SANS}; font-size: 11.5px; paint-order: stroke; stroke-width: 4px; stroke-linejoin: round; }}
.t-code {{ font-family: {MONO}; font-size: 13px; font-weight: 600; }}
.t-small {{ font-size: 12px; }}
.t-type {{ font-family: {MONO}; font-size: 11.5px; }}
.t-bound {{ font-family: {MONO}; font-size: 12px; font-weight: 600; }}
.edge {{ fill: none; stroke-width: 1.25; }}
.edge-later {{ fill: none; stroke-width: 1.25; stroke-dasharray: 5 4; }}
.bg {{ fill: #FFFFFF; }}
.b-sys {{ fill: #F5E9CC; stroke: #A56F0A; stroke-width: 2; }}
.b-ext {{ fill: #ECEFED; stroke: #8A9791; stroke-width: 1.25; }}
.b-per {{ fill: #E3EBF2; stroke: #3B5B7A; stroke-width: 1.25; }}
.b-cmp {{ fill: #FFFFFF; stroke: #8A9791; stroke-width: 1.25; }}
.b-later {{ fill: none; stroke: #8A9791; stroke-width: 1.25; stroke-dasharray: 5 4; }}
.bound {{ fill: none; stroke: #66736E; stroke-width: 1.25; stroke-dasharray: 7 5; }}
.bound-in {{ fill: none; stroke: #D9DFDC; stroke-width: 1.5; stroke-dasharray: 4 4; }}
.head {{ fill: #3B5B7A; }}
.t-name {{ fill: #16201D; }}
.t-code {{ fill: #16201D; }}
.t-type {{ fill: #66736E; }}
.t-desc {{ fill: #34413C; }}
.t-bound {{ fill: #66736E; }}
.t-rel {{ fill: #66736E; stroke: #FFFFFF; }}
.edge, .edge-later {{ stroke: #8A9791; }}
.arrowhead {{ fill: #8A9791; }}
@media (prefers-color-scheme: dark) {{
.bg {{ fill: #171F1C; }}
.b-sys {{ fill: #3A2E13; stroke: #E3AA3C; stroke-width: 2; }}
.b-ext {{ fill: #1C2421; stroke: #7D8B85; stroke-width: 1.25; }}
.b-per {{ fill: #1D2A36; stroke: #8EB4D8; stroke-width: 1.25; }}
.b-cmp {{ fill: #171F1C; stroke: #7D8B85; stroke-width: 1.25; }}
.b-later {{ fill: none; stroke: #7D8B85; stroke-width: 1.25; stroke-dasharray: 5 4; }}
.bound {{ fill: none; stroke: #93A09A; stroke-width: 1.25; stroke-dasharray: 7 5; }}
.bound-in {{ fill: none; stroke: #2A3431; stroke-width: 1.5; stroke-dasharray: 4 4; }}
.head {{ fill: #8EB4D8; }}
.t-name {{ fill: #E6ECE9; }}
.t-code {{ fill: #E6ECE9; }}
.t-type {{ fill: #93A09A; }}
.t-desc {{ fill: #C3CDC8; }}
.t-bound {{ fill: #93A09A; }}
.t-rel {{ fill: #93A09A; stroke: #171F1C; }}
.edge, .edge-later {{ stroke: #7D8B85; }}
.arrowhead {{ fill: #7D8B85; }}
}}
</style>"""

DEFS = ('<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
        'markerHeight="7" orient="auto-start-reverse"><path class="arrowhead" '
        'd="M0 0L10 5L0 10z"/></marker></defs>')


class Svg:
    def __init__(self, w, h, label):
        self.w, self.h, self.label = w, h, label
        self.parts = []

    def text(self, cls, x, y, s, anchor=None, rotate=None):
        a = f' text-anchor="{anchor}"' if anchor else ""
        r = f' transform="rotate({rotate} {x} {y})"' if rotate is not None else ""
        self.parts.append(f'<text class="{cls}" x="{x}" y="{y}"{a}{r}>{escape(s)}</text>')

    def rect(self, cls, x, y, w, h, rx=10):
        self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}"/>')

    def element(self, cls, x, y, w, h, name, kind, desc, person=False):
        """A context or container element: name, [kind], description lines."""
        self.rect(cls, x, y, w, h)
        tx = x + 16
        if person:
            self.parts.append(f'<circle class="head" cx="{x + 26}" cy="{y + 24}" r="9"/>')
            tx = x + 44
        self.text("t-name", tx, y + 28, name)
        self.text("t-type", tx, y + 46, kind)
        for i, line in enumerate(desc):
            self.text("t-desc", x + 16, y + 70 + 16 * i, line)

    def component(self, cls, x, y, w, h, name, kind, desc, small=False):
        """A component: code name, [kind] right-aligned (or below when small)."""
        self.rect(cls, x, y, w, h, rx=8)
        self.text("t-code t-small" if small else "t-code", x + 14, y + 24, name)
        if small:
            self.text("t-type", x + 14, y + 42, kind)
            y0 = y + 62
        else:
            self.text("t-type", x + w - 12, y + 24, kind, anchor="end")
            y0 = y + 46
        for i, line in enumerate(desc):
            self.text("t-desc", x + 14, y0 + 16 * i, line)

    def row(self, cls, x, y, w, name, desc):
        """A one-line desk: name on the left, what it does on the right."""
        self.rect(cls, x, y, w, 34, rx=8)
        self.text("t-code t-small", x + 12, y + 22, name)
        self.text("t-desc", x + w - 12, y + 22, desc, anchor="end")

    def bound(self, cls, x, y, w, h, label):
        self.rect(cls, x, y, w, h, rx=12 if cls == "bound" else 10)
        self.text("t-bound", x + 16, y + 22, label)

    def edge(self, d, later=False):
        c = "edge-later" if later else "edge"
        self.parts.append(f'<path class="{c}" d="{d}" marker-end="url(#a)"/>')

    def write(self, name):
        head = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" role="img" '
                f'aria-label="{escape(self.label)}">',
                f"<title>{escape(self.label)}</title>", STYLE, DEFS,
                f'<rect class="bg" x="0" y="0" width="{self.w}" height="{self.h}"/>', ""]
        with open(os.path.join(ASSETS, name), "w") as f:
            f.write("\n".join(head + self.parts + ["</svg>", ""]))


# ---------------------------------------------------------------------------
# Level 1: system context
# ---------------------------------------------------------------------------
def context():
    s = Svg(1000, 620, "mcl-agora system context")

    # Edges first, so boxes and labels sit on top.
    s.edge("M180 140V175H450V200")               # the square -> mcl-agora
    s.edge("M500 140V200")                       # reader -> mcl-agora
    s.edge("M250 265H370")                       # macula-mcp -> mcl-agora
    s.edge("M630 265H800V140", later=True)       # mcl-agora -> portal page (planned)
    s.edge("M420 330V440")                       # mcl-agora -> station
    s.edge("M580 330V440")                       # mcl-agora -> realm

    s.element("b-ext", 40, 30, 280, 110, "The square", "[External: the speaker's topics]",
              ["mcl-spartan's minds publish", "agora_post_published_v1 here; the", "keeper only ever subscribes"])
    s.element("b-per", 380, 30, 240, 110, "Reader", "[Person or agent]",
              ["Calls mcl-agora/get_posts_page,", "or follows the record as it grows", "on agora_post_recorded_v1"], person=True)
    s.element("b-later", 750, 30, 230, 110, "Portal page", "[Planned: W1c]",
              ["The page that reads the record", "on macula.io. Not built, and not", "part of W1a."])

    s.element("b-ext", 20, 200, 230, 130, "macula-mcp", "[External: MCP server]",
              ["Outside the fleet. Its generic", "mesh_call reaches", "mcl-agora/get_posts_page; there", "is no agora tool"])
    s.element("b-sys", 370, 200, 260, 130, "mcl-agora", "[Software system, mcl_om service]",
              ["The agora's record keeper:", "records every post it hears,", "answers get_posts_page, and", "announces each recording"])

    s.element("b-ext", 230, 440, 250, 110, "macula-station", "[External system]",
              ["Pinned home station(s);", "carries every call and fact", "to and from this node"])
    s.element("b-ext", 520, 440, 250, 110, "macula-realm", "[External system]",
              ["Boot identity claim; a D25", "provider grant for get_posts_page;", "the realm key is the anchor"])

    s.text("t-rel", 300, 168, "publishes; the keeper subscribes", anchor="middle")
    s.text("t-rel", 492, 175, "calls", anchor="end")
    s.text("t-rel", 492, 189, "(not sealed)", anchor="end")
    s.text("t-rel", 310, 256, "get_posts_page", anchor="middle")
    s.text("t-rel", 690, 258, "publishes agora_post_recorded_v1", anchor="middle")
    s.text("t-rel", 412, 386, "dials out,", anchor="end")
    s.text("t-rel", 412, 400, "pinned (QUIC, pq_hybrid)", anchor="end")
    s.text("t-rel", 588, 386, "claims its identity,")
    s.text("t-rel", 588, 400, "gets a grant for get_posts_page")
    s.text("t-rel", 20, 600, "Every call and fact travels over the mesh, through the station. W1b adds the first mind; W2 the publisher and stimulus cross-checks; W3 threads; W6 search and the archive.")
    s.write("c4-context.svg")


# ---------------------------------------------------------------------------
# Level 2: containers
# ---------------------------------------------------------------------------
def containers():
    s = Svg(1000, 640, "mcl-agora containers")

    s.bound("bound", 220, 40, 560, 560, "a fleet box [planned: docker, host networking, /bulk0 mounted]")
    s.bound("bound-in", 236, 72, 528, 500, "mcl-agora [Software system, mcl_om service]")

    # Edges
    s.edge("M200 136H260")                     # macula-mcp
    s.edge("M200 230H260")                     # the square
    s.edge("M200 316H260")                     # reader
    s.edge("M740 134H810")                     # station
    s.edge("M740 228H810")                     # realm
    s.edge("M740 310H810")                     # record readers
    s.edge("M372 300V335")                     # event store
    s.edge("M627 300V335")                     # identity key

    s.element("b-sys", 260, 100, 480, 200, "mcl-agora service",
              "[Container: OCI image, OTP 28.4.3 release, mcl_om 0.39]",
              ["One open procedure as mcl-agora/get_posts_page v1 (not sealed), and",
               "mcl-om's mcl-agora/info (macula 14.2). Subscribes to the square's",
               "agora_post_published_v1; publishes agora_post_recorded_v1 on its own",
               "record topic. From mcl-om: node identity, pinned station dial, realm",
               "claim, the provider grant, /health on a Unix socket. Its own reckon-db",
               "store opens before mcl-om's boot; the read model is in memory and",
               "rebuilt from that store on every boot."])

    s.element("b-cmp", 260, 335, 225, 120, "Event store", "[bind mount: /data]",
              ["/bulk0/mcl-agora on a node.", "mcl_agora_store under MCL_DATA_DIR:", "the event log that IS the record,", "replayed into the read model on boot"])
    s.element("b-cmp", 515, 335, 225, 120, "Identity key", "[mcl-agora-secrets]",
              ["/etc/mcl/secrets:", "identity.key, the node id the", "realm admits and grants"])
    s.rect("b-cmp", 260, 480, 480, 56)
    s.text("t-code t-small", 276, 504, "posts read model")
    s.text("t-desc", 276, 522, "ETS, in memory: agora_posts (by posted_at) and agora_posts_by_id. Rebuilt on boot.")

    s.element("b-ext", 10, 96, 190, 80, "macula-mcp", "[MCP server]",
              ["outside the fleet"])
    s.element("b-ext", 10, 190, 190, 80, "The square", "[speaker-owned]",
              ["agora_post_published_v1"])
    s.element("b-ext", 10, 276, 190, 80, "Reader", "[mesh callers]",
              ["get_posts_page"])

    s.element("b-ext", 810, 96, 180, 76, "macula-station", "[pinned seed(s)]", [])
    s.element("b-ext", 810, 190, 180, 76, "macula-realm", "[trust anchor]", [])
    s.element("b-ext", 810, 280, 180, 90, "Record readers", "[subscribers]",
              ["agora_post_recorded_v1"])

    s.text("t-rel", 230, 128, "calls", anchor="middle")
    s.text("t-rel", 230, 222, "subscribe", anchor="middle")
    s.text("t-rel", 230, 308, "reads", anchor="middle")
    s.text("t-rel", 10, 390, "all over the mesh, via the station")
    s.text("t-rel", 775, 126, "dials", anchor="middle")
    s.text("t-rel", 775, 220, "claims", anchor="middle")
    s.text("t-rel", 775, 302, "announces", anchor="middle")
    s.text("t-rel", 380, 325, "appends, replays")
    s.text("t-rel", 635, 325, "loads")
    s.write("c4-containers.svg")


# ---------------------------------------------------------------------------
# Level 3: components of the service
# ---------------------------------------------------------------------------
def components():
    s = Svg(1240, 1220, "mcl-agora components")
    s.bound("bound", 200, 40, 760, 1052, "mcl-agora service [Container]")

    # The facade: the mcl_om service contract, and the app that opens the store.
    s.bound("bound-in", 216, 72, 728, 132, "apps/mcl_agora [the facade: the mcl_om service contract and the store wiring]")
    s.component("b-cmp", 232, 104, 344, 88, "mcl_agora_service", "[mcl_om_service]",
                ["Six required callbacks and three optional:",
                 "subscriptions/0 the square; event_store/0 and",
                 "data_dir/0 this service's own reckon-db store."])
    s.component("b-cmp", 588, 104, 344, 88, "mcl_agora_app + mcl_agora_store", "[OTP application]",
                ["Opens the store and its evoq subscription, then mcl_om:boot/1."], small=True)

    # CMD: the input, the command, the aggregate, the emitter.
    s.bound("bound-in", 216, 216, 728, 132, "apps/guide_agora_post_lifecycle [CMD: hears the square, records one post, says it out loud]")
    s.component("b-cmp", 232, 248, 712, 88, "the listener + agora_post_fact", "[macula_subscriber]",
                ["on_agora_post_published_from_mesh_maybe_record_agora_post is the keeper's only input; it reads the square's",
                 "wire shape and refuses a fact with no verified publisher, or no usable post_id, from, body or posted_at."], small=True)

    s.bound("bound-in", 216, 360, 728, 132, "the command and the aggregate [one stream per post, keyed by the post_id the speaker minted]")
    s.component("b-cmp", 232, 392, 320, 88, "record_agora_post_v1 + handler", "[command -> maybe_record_agora_post]",
                ["Dispatches one evoq_command per", "post_id, stream agora-post-<id>."], small=True)
    s.component("b-cmp", 596, 392, 348, 88, "agora_post_aggregate + state", "[evoq_aggregate, bit-flag status]",
                ["A repeat is refused with {ok, []}; that", "refusal IS the idempotency."], small=True)

    # The store: what the aggregate appends to and every handler replays from.
    s.bound("bound-in", 216, 504, 728, 120, "evoq 1.26 / reckon_evoq 2.7 [the CQRS framework and its adapter]")
    s.component("b-cmp", 232, 536, 712, 88, "mcl_agora_store", "[reckon-db 5.4, under MCL_DATA_DIR]",
                ["The event log that IS the record: append-only on disk, replayed to every handler on each boot, and the",
                 "only thing that survives a restart. The read model is built from this, never the other way round."])

    # The store's two readers, side by side: the projection (PRJ) and the emitter (CMD).
    s.component("b-sys", 232, 660, 344, 116, "agora_post_recorded_v1_to_posts", "[evoq_projection, PRJ]",
                ["One event, one row; a replayed event", "rewrites the row it already wrote, which", "is what lets a boot rebuild the model."], small=True)
    s.component("b-sys", 588, 660, 344, 116, "emit_agora_post_recorded_v1_to_mesh", "[evoq_event_handler, replay skip, CMD]",
                ["Subscribes to the store, so it announces", "only what was written. replay_policy ->",
                 "skip: a boot never re-announces the record."], small=True)

    s.component("b-cmp", 232, 808, 344, 120, "project_agora_posts_store", "[gen_server, ETS]",
                ["agora_posts: ordered_set keyed", "{posted_at, post_id}, so a page is a",
                 "bounded walk, not a sort of the record;", "agora_posts_by_id the point lookup."], small=True)
    s.component("b-cmp", 232, 960, 344, 120, "get_posts_page + responder", "[query, macula_response]",
                ["mcl-agora/get_posts_page: newest first,", "cursor-paged by next_before (omitted on",
                 "the last page, never a sentinel). The", "responder is a thin wire wrapper."], small=True)

    # External to the container.
    s.element("b-ext", 10, 976, 180, 110, "macula-mcp / caller", "[MCP server or caller]",
              ["mesh_call reaches", "mcl-agora/get_posts_page;", "the record is readable"])
    s.element("b-ext", 980, 104, 220, 88, "macula-realm", "[trust anchor]",
              ["claim, provider grant,", "realm key"])
    s.element("b-ext", 980, 232, 220, 110, "The square", "[speaker-owned topics]",
              ["the minds publish", "agora_post_published_v1 here;", "the keeper only subscribes"])
    s.element("b-ext", 980, 372, 220, 88, "macula-station", "[pinned]",
              ["carries the procedure,", "info and every fact"])
    s.element("b-ext", 980, 840, 220, 100, "Record readers", "[subscribers]",
              ["follow agora_post_recorded_v1", "as the record grows"])
    s.element("b-ext", 232, 1120, 344, 64, "Event store on disk", "[/data, a bind mount; /bulk0/mcl-agora on a node]", [])

    # Edges and labels
    s.edge("M400 204V248"); s.text("t-rel", 408, 222, "subscriptions/0 starts the subscriber")
    s.edge("M400 348V392"); s.text("t-rel", 408, 366, "a fact becomes a command")
    s.edge("M552 436H596"); s.text("t-rel", 574, 452, "dispatch", anchor="middle")
    s.edge("M770 480V536"); s.text("t-rel", 778, 500, "one event per post;")
    s.text("t-rel", 778, 514, "a repeat is refused")
    s.edge("M404 624V660"); s.text("t-rel", 412, 636, "replayed")
    s.text("t-rel", 412, 650, "on boot")
    s.edge("M770 624V660"); s.text("t-rel", 778, 636, "each stored")
    s.text("t-rel", 778, 650, "event")
    s.edge("M404 776V808"); s.text("t-rel", 412, 786, "writes")
    s.edge("M404 928V960"); s.text("t-rel", 412, 938, "reads")
    s.edge("M932 718H968V890H980"); s.text("t-rel", 976, 800, "agora_post_recorded_v1")
    s.edge("M980 287H944"); s.text("t-rel", 962, 279, "hears", anchor="middle")
    s.edge("M980 148H932"); s.text("t-rel", 956, 140, "claims", anchor="middle")
    s.edge("M980 416H968V580H944"); s.text("t-rel", 976, 470, "carries calls")
    s.edge("M232 1020H190"); s.text("t-rel", 218, 1012, "calls", anchor="middle")
    s.edge("M404 1080V1120"); s.text("t-rel", 412, 1096, "the record")
    s.text("t-rel", 20, 1200, "W1a records and answers. W1b adds the first mind, W1c the portal page, W2 the publisher and stimulus cross-checks and post_conflict_detected, W3 threads and synthesis, W6 search and the archive: none of them drawn.")
    s.write("c4-components.svg")


if __name__ == "__main__":
    os.makedirs(ASSETS, exist_ok=True)
    context()
    containers()
    components()
