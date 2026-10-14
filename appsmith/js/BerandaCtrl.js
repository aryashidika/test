export default {
	loading: false,
	loaded: false,

	// ---- muat data ----
	queries() {
		const role = (Auth.me && Auth.me.role) || '';
		return {
			VENDOR_SPEC: [q_worklist_spec],
			VENDOR_CBD: [q_worklist_cbd, q_worklist_gap, q_worklist_rejected],
			MANAGER_COSTING: [q_worklist_admin],
			BRAND_VIEWER: [q_worklist_pub_spec, q_worklist_pub_cbd],
			SYSTEM_ADMIN: [q_worklist_system],
		}[role] || [];
	},

	// Jalankan semua query role ini bersamaan. Sesi habis -> Login; error lain -> satu pesan.
	async load() {
		this.loading = true;
		const results = await Promise.all(this.queries().map(q => q.run().then(() => null, e => e || new Error('Failed'))));
		this.loading = false;
		this.loaded = true;
		const failed = results.find(r => r);
		if (!failed) return true;
		const msg = failed.message;
		if (Util.isSessionError(msg)) {
			await removeValue('token');
			showAlert('Session expired. Please log in again.', 'warning');
			navigateTo('Login');
			return false;
		}
		showAlert(Util.cleanError(msg), 'error');
		return false;
	},

	// cwWorklist onRefresh
	reload() {
		return this.load();
	},

	// cwWorklist onOpen - baca tujuan dari model widget
	open() {
		const m = cwWorklist.model || {};
		if (!m.target) return;
		navigateTo(m.target, m.params || {});
	},

	// ---- tujuan klik ----
	toSpec(r) {
		return { target: 'Specsheet', params: { model_id: r.model_id, season: r.specsheet_id, from: 'home' } };
	},

	toCbd(r) {
		return { target: 'Cost Breakdown (CBD)', params: { model_id: r.model_id, season: r.specsheet_id, article: r.article_id, from: 'home' } };
	},

	toMaterial(r) {
		return { target: 'Material Detail', params: { id: r.material_id } };
	},

	// ---- model widget ----
	// Default model cwWorklist: {{BerandaCtrl.model()}}
	model() {
		const me = Auth.me;
		const base = {
			loaded: !!me && this.loaded, loading: this.loading,
			title: 'My Tasks', subtitle: '', columns: 1, stats: [], sections: [],
		};
		if (!me) return base;
		const part = {
			VENDOR_SPEC: () => this.specModel(),
			VENDOR_CBD: () => this.cbdModel(),
			MANAGER_COSTING: () => this.adminModel(),
			BRAND_VIEWER: () => this.brandModel(),
			SYSTEM_ADMIN: () => this.systemModel(),
		}[me.role];
		return Object.assign(base, part ? part() : {});
	},

	// ---- Vendor Spec ----
	draftFlags(d) {
		const flags = [];
		const unusedCount = d.unused_articles ? String(d.unused_articles).split(', ').length : 0;
		if (unusedCount) flags.push({ text: `${unusedCount} articles not used in the BOM`, tone: 'warn', hint: d.unused_articles });
		if (Number(d.no_supplier) > 0) flags.push({ text: `${d.no_supplier} lines without supplier`, tone: 'warn' });
		if (d.inactive_materials) flags.push({ text: 'Has INACTIVE materials', tone: 'danger', hint: d.inactive_materials });
		if (Number(d.yellow_cells) > 0) flags.push({ text: `${d.yellow_cells} yellow cells (no Material Code)`, tone: 'warn' });
		if (d.inactive_suppliers) flags.push({ text: 'Has inactive suppliers', tone: 'danger', hint: d.inactive_suppliers });
		if (!Number(d.article_count)) flags.push({ text: 'No active articles', tone: 'warn' });
		if (!Number(d.line_count)) {
			flags.push({ text: 'BOM is empty', tone: 'info' });
		} else if (flags.length === 0) {
			flags.push({ text: 'No blockers found', tone: 'ok' });
		}
		return flags;
	},


	specModel() {
		const rows = q_worklist_spec.data || [];
		const drafts = rows.filter(r => r.kind === 'DRAFT');
		const unassigned = rows.filter(r => r.kind === 'UNASSIGNED');
		const unassignedTotal = unassigned.reduce((n, r) => n + (Number(r.article_count) || 0), 0);
		const yellowTotal = drafts.reduce((n, r) => n + (Number(r.yellow_cells) || 0), 0);
		return {
			subtitle: 'Specsheet drafts and articles waiting for you.',
			stats: [
				{ key: 'drafts', value: drafts.length, label: 'Open specsheet drafts', tone: 'info' },
				{ key: 'unassigned', value: unassignedTotal, label: 'Articles not in a specsheet', tone: 'warn' },
				{ key: 'drafts', value: yellowTotal, label: 'Yellow cells (Material Code not registered)', tone: 'warn' },
			],
			sections: [
				{
					key: 'drafts', title: 'Specsheet Drafts', empty: 'No open specsheet drafts.',
					items: drafts.map(d => Object.assign({
						title: `${d.model_name} · ${d.season} · ${Util.revLabel(d)}`,
						meta: `${d.line_count} BOM lines · ${d.article_count} active articles`,
						flags: this.draftFlags(d),
					}, this.toSpec(d))),
				},
				{
					key: 'unassigned', title: 'Articles Not in a Specsheet', empty: 'All articles are in a specsheet.',
					items: unassigned.map(u => Object.assign({
						title: `${u.model_name} · ${u.season}`,
						meta: u.article_codes,
						flags: [{ text: u.has_revision ? 'Select it in the specsheet revision' : 'No specsheet yet', tone: 'muted' }],
					}, this.toSpec(u))),
				},
			],
		};
	},

	// ---- Vendor CBD ----
	cbdItem(r, flag) {
		const flags = flag ? [flag] : [];
		if (Number(r.pending_prices) > 0) {
			flags.push({ text: `${r.pending_prices} prices waiting for approval`, tone: 'warn', hint: 'CBD cannot be published yet' });
		}
		return Object.assign({
			title: `${r.model_name} · ${r.season} · ${r.article_code}`,
			meta: r.colorway + (r.rev_label ? ` · ${r.rev_label}` : ''),
			flags,
		}, this.toCbd(r));
	},

	cbdModel() {
		const rows = q_worklist_cbd.data || [];
		const of = kind => rows.filter(r => r.kind === kind);
		const gaps = q_worklist_gap.data || [];
		const rejected = q_worklist_rejected.data || [];
		const refreshFlag = r => ({
			text: r.refresh_reason === 'SPEC' ? 'Reference specsheet was revised' : 'Master price changed', tone: 'warn',
		});
		return {
			subtitle: 'CBD and material price work to follow up.',
			stats: [
				{ key: 'to-create', value: of('TO_CREATE').length, label: 'CBD to create', tone: 'info' },
				{ key: 'to-refresh', value: of('TO_REFRESH').length, label: 'Drafts to refresh', tone: 'warn' },
				{ key: 'to-revise', value: of('TO_REVISE').length, label: 'Published CBD to revise', tone: 'warn' },
				{ key: 'price-gaps', value: gaps.length, label: 'Missing master prices', tone: 'warn' },
				{ key: 'price-rejected', value: rejected.length, label: 'Rejected price proposals', tone: 'warn' },
			],
			sections: [
				{
					key: 'to-create', title: 'CBD to Create', empty: 'All active articles have a CBD.',
					items: of('TO_CREATE').map(r => this.cbdItem(r, { text: 'Active in published specsheet', tone: 'muted' })),
				},
				{
					key: 'to-refresh', title: 'CBD Drafts to Refresh',
					empty: 'No drafts behind the specsheet or master prices.',
					items: of('TO_REFRESH').map(r => this.cbdItem(r, refreshFlag(r))),
				},
				{
					key: 'to-revise', title: 'Published CBD to Revise', empty: 'All published CBDs match the specsheet.',
					items: of('TO_REVISE').map(r => this.cbdItem(r, r.refresh_reason === 'STAGE'          // R13
						? { text: 'Specsheet is at a later stage. Create its CBD', tone: 'warn' }
						: { text: 'NEEDS REVISION', tone: 'warn' })),
				},
				{
					key: 'in-progress', title: 'CBD Drafts in Progress', hideWhenEmpty: true, empty: '',
					items: of('IN_PROGRESS').map(r => this.cbdItem(r, { text: 'DRAFT', tone: 'info' })),
				},
				{
					key: 'price-gaps', title: 'Missing Master Prices',
					note: 'Material variants + suppliers used in published specsheets without an active price.',
					empty: 'All used materials have a master price.',
					items: gaps.map(g => Object.assign({
						title: g.material_name,
						meta: `Supplier ${g.supplier_name} · used in ${g.models}`,
						flags: [].concat(
							Number(g.variant_count) > 0 ? [{ text: `${g.variant_count} Material Codes without price`, tone: 'warn', hint: g.codes }] : [],
							g.has_pending ? [{ text: 'Price proposal waiting for approval', tone: 'info' }] : []
						),
					}, this.toMaterial(g))),
				},
				{
					key: 'price-rejected', title: 'Rejected Price Proposals',
					note: 'Rejected by Manager Costing in the last 30 days and not proposed again.',
					empty: 'No rejected price proposals.', hideWhenEmpty: true,
					items: rejected.map(x => Object.assign({
						title: `${x.material_name} · ${x.code}`,
						meta: `${x.supplier_name} · ${x.currency} ${Util.fmtNum(x.price, x.currency === 'USD' ? 4 : 0)} · rejected by ${x.decided_by || '-'} ${Util.fmtDateTime(x.decided_at)}`,
						flags: [{ text: `Reason: ${x.reject_reason || '-'}`, tone: 'danger' }],
					}, this.toMaterial(x))),
				},
			],
		};
	},

	// ---- Manager Costing (R3: satu baris per pengajuan harga -> page Persetujuan Harga) ----
	adminItem(r) {
		const nav = { target: 'Price Approval', params: { batch: r.ref_id } };
		const meta = [r.detail, r.amount_text, `proposed by ${r.proposed_by || '-'}`, Util.fmtDateTime(r.proposed_at)]
			.filter(x => x).join(' · ');
		return Object.assign({ title: r.title, meta, flags: [] }, nav);
	},

	adminModel() {
		const rows = q_worklist_admin.data || [];
		const of = kind => rows.filter(r => r.kind === kind);
		const section = (key, kind, title, empty, note) => ({
			key, title, note, empty, items: of(kind).map(r => this.adminItem(r)),
		});
		return {
			subtitle: 'Price proposals waiting for your approval.',
			stats: [
				{ key: 'appr-prices', value: of('PRICE').length, label: 'Price proposals', tone: 'warn' },
			],
			sections: [
				section('appr-prices', 'PRICE', 'Price Proposals Waiting for Approval', 'No price proposals.',
					'Vendor CBD proposals (per submission). The old price stays active until approved.'),
			],
		};
	},

	// ---- Brand ----
	brandModel() {
		const specs = q_worklist_pub_spec.data || [];
		const cbds = q_worklist_pub_cbd.data || [];
		return {
			subtitle: 'Recently published specsheets and CBDs.',
			columns: 2,
			sections: [
				{
					key: 'pub-spec', title: 'Latest Published Specsheets', note: 'Latest published revision per season.',
					empty: 'No published specsheets yet.',
					items: specs.map(r => Object.assign({
						title: `${r.model_name} · ${r.season} · ${Util.revLabel(r)}`,
						meta: `${r.factory_name} · published ${Util.fmtDateTime(r.published_at)}`,
						flags: [],
					}, this.toSpec(r))),
				},
				{
					key: 'pub-cbd', title: 'Latest Published CBDs', note: 'Latest published revision per article.',
					empty: 'No published CBDs yet.',
					items: cbds.map(r => Object.assign({
						title: `${r.model_name} · ${r.article_code} · ${Util.revLabel(r)}`,
						meta: `${r.colorway} · published ${Util.fmtDateTime(r.published_at)}`,
						flags: r.sync_status === 'NEEDS_REVISION' ? [{ text: 'NEEDS REVISION', tone: 'warn' }] : [],
					}, this.toCbd(r))),
				},
			],
		};
	},

	// ---- System Admin ----
	systemModel() {
		const s = (q_worklist_system.data && q_worklist_system.data[0]) || null;
		const n = v => Util.fmtNum(s ? v : 0);
		// R11 (S7/S8): ukuran audit log + peringatan bila > 3 GB (tidak ada penghapusan otomatis)
		const bytes = s ? Number(s.audit_size_bytes) || 0 : 0;
		const size = bytes >= 1073741824 ? `${Util.fmtNum(bytes / 1073741824, 1)} GB` : `${Util.fmtNum(Math.max(1, Math.round(bytes / 1048576)))} MB`;
		const big = bytes > 3 * 1073741824;
		return {
			subtitle: 'System summary.',
			stats: s ? [
				{ key: 'sys', value: s.models, label: 'Model', tone: '' },
				{ key: 'sys', value: s.specsheets, label: 'Specsheet (season)', tone: '' },
				{ key: 'sys', value: s.cbd_revisions, label: 'CBD revisions', tone: '' },
				{ key: 'sys', value: s.audit_entries, label: 'Audit log entries (±)', tone: '' },
			] : [],
			sections: [{
				key: 'sys', title: 'System Summary', empty: 'Summary data could not be loaded.',
				items: s ? [{
					title: `${n(s.materials)} materials · ${n(s.articles)} articles · ${n(s.active_users)} active users`,
					meta: `Last activity ${Util.fmtDateTime(s.last_audit)}. Open the Admin menu for users and the audit log.`,
					target: 'Admin', params: {},
				}, {
					title: `Audit log ${size}`,
					meta: big ? 'Over 3 GB. Time to archive the old audit log (contact the developer).'
						: 'Warning limit 3 GB. The audit log is not deleted automatically.',
					flags: big ? [{ text: 'ARCHIVE NEEDED', tone: 'warn' }] : [],
					target: 'Admin', params: {},
				}] : [],
			}],
		};
	},
}
