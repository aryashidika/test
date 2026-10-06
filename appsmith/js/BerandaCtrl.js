// JSObject "BerandaCtrl" — page Beranda: "Tugas Saya" (cwWorklist) sesuai role, di atas menu (cwMenu).
// Per role (satu daftar saja, sama dengan Python):
//   VENDOR_SPEC  — draft specsheet terbuka · article belum masuk specsheet · usulan master data
//   VENDOR_CBD   — CBD perlu dibuat · draft perlu refresh · CBD terbit perlu revisi · draft berjalan · harga master belum ada
//   MASTER_ADMIN — usulan menunggu persetujuan: supplier · material · komponen · supplier material · harga
//   BRAND_VIEWER — specsheet & CBD terbit terbaru
//   SYSTEM_ADMIN — ringkasan sistem
// Data dari view v_worklist_* / v_recent_published / v_system_summary (SQL F10), dibaca lewat query q_worklist_*.
// Query yang dijalankan hanya milik role-nya (queries()); izin dicek lagi di DB. Dijalankan Auth.pageQueries()
// dan tombol Muat ulang di cwWorklist. Klik tugas -> halaman tujuan lewat cwWorklist.onOpen -> open();
// parameter from=home membuat tombol kembali di Specsheet / CBD mengarah ke Beranda.
export default {
	loading: false,
	loaded: false,

	// ---- muat data ----
	queries() {
		const role = (Auth.me && Auth.me.role) || '';
		return {
			VENDOR_SPEC: [q_worklist_spec, q_worklist_proposals],
			VENDOR_CBD: [q_worklist_cbd, q_worklist_gap],
			MASTER_ADMIN: [q_worklist_admin],
			BRAND_VIEWER: [q_worklist_pub_spec, q_worklist_pub_cbd],
			SYSTEM_ADMIN: [q_worklist_system],
		}[role] || [];
	},

	// Jalankan semua query role ini bersamaan. Sesi habis -> Login; error lain -> satu pesan.
	async load() {
		this.loading = true;
		const results = await Promise.all(this.queries().map(q => q.run().then(() => null, e => e || new Error('Gagal'))));
		this.loading = false;
		this.loaded = true;
		const failed = results.find(r => r);
		if (!failed) return true;
		const msg = failed.message;
		if (Util.isSessionError(msg)) {
			await removeValue('token');
			showAlert('Sesi login habis. Silakan login lagi.', 'warning');
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

	// cwWorklist onOpen — baca tujuan dari model widget
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
			title: 'Tugas Saya', subtitle: '', columns: 1, stats: [], sections: [],
		};
		if (!me) return base;
		const part = {
			VENDOR_SPEC: () => this.specModel(),
			VENDOR_CBD: () => this.cbdModel(),
			MASTER_ADMIN: () => this.adminModel(),
			BRAND_VIEWER: () => this.brandModel(),
			SYSTEM_ADMIN: () => this.systemModel(),
		}[me.role];
		return Object.assign(base, part ? part() : {});
	},

	// ---- Vendor Spec ----
	draftFlags(d) {
		const flags = [];
		const unusedCount = d.unused_articles ? String(d.unused_articles).split(', ').length : 0;
		if (unusedCount) flags.push({ text: `${unusedCount} article belum dipakai di BOM`, tone: 'warn', hint: d.unused_articles });
		if (Number(d.no_supplier) > 0) flags.push({ text: `${d.no_supplier} baris tanpa supplier`, tone: 'warn' });
		if (d.inactive_materials) flags.push({ text: 'Ada material INACTIVE', tone: 'danger', hint: d.inactive_materials });
		if (d.proposed_items) flags.push({ text: 'Usulan belum di-approve', tone: 'warn', hint: d.proposed_items });
		if (!Number(d.article_count)) flags.push({ text: 'Belum ada article aktif', tone: 'warn' });
		if (!Number(d.line_count)) {
			flags.push({ text: 'BOM masih kosong', tone: 'info' });
		} else if (flags.length === 0) {
			flags.push({ text: 'Tidak ada penghambat terdeteksi', tone: 'ok' });
		}
		return flags;
	},

	proposalCounts() {
		const c = { SUPPLIER: 0, MATERIAL: 0, COMPONENT: 0, LINK: 0 };
		(q_worklist_proposals.data || []).forEach(r => { c[r.kind] = Number(r.n) || 0; });
		return c;
	},

	specModel() {
		const rows = q_worklist_spec.data || [];
		const drafts = rows.filter(r => r.kind === 'DRAFT');
		const unassigned = rows.filter(r => r.kind === 'UNASSIGNED');
		const unassignedTotal = unassigned.reduce((n, r) => n + (Number(r.article_count) || 0), 0);
		const c = this.proposalCounts();
		const proposalTotal = c.SUPPLIER + c.MATERIAL + c.COMPONENT + c.LINK;
		return {
			subtitle: 'Draft specsheet dan article yang menunggu Anda.',
			stats: [
				{ key: 'drafts', value: drafts.length, label: 'Draft specsheet terbuka', tone: 'info' },
				{ key: 'unassigned', value: unassignedTotal, label: 'Article belum masuk specsheet', tone: 'warn' },
				{ key: 'proposals', value: proposalTotal, label: 'Usulan menunggu persetujuan', tone: '' },
			],
			sections: [
				{
					key: 'drafts', title: 'Draft Specsheet', empty: 'Tidak ada draft specsheet yang terbuka.',
					items: drafts.map(d => Object.assign({
						title: `${d.model_code} · ${d.season} — ${d.stage} r${d.revision_no}`,
						meta: `${d.model_name} · ${d.line_count} baris BOM · ${d.article_count} article aktif`,
						flags: this.draftFlags(d),
					}, this.toSpec(d))),
				},
				{
					key: 'unassigned', title: 'Article Belum Masuk Specsheet', empty: 'Semua article sudah masuk specsheet.',
					items: unassigned.map(u => Object.assign({
						title: `${u.model_code} · ${u.season}`,
						meta: u.article_codes,
						flags: [{ text: u.has_revision ? 'Pilih di revisi specsheet' : 'Specsheet belum dibuat', tone: 'muted' }],
					}, this.toSpec(u))),
				},
				{
					key: 'proposals', title: 'Usulan Master Data', empty: 'Tidak ada usulan yang menunggu.',
					items: proposalTotal ? [{
						title: `${c.SUPPLIER} supplier · ${c.MATERIAL} material · ${c.COMPONENT} komponen · ${c.LINK} supplier material`,
						meta: 'Menunggu persetujuan Master Admin. Usulan sudah bisa dipakai di BOM, tetapi specsheet baru bisa terbit setelah semuanya disetujui.',
						target: 'Master Material', params: {},
					}] : [],
				},
			],
		};
	},

	// ---- Vendor CBD ----
	cbdItem(r, flag) {
		return Object.assign({
			title: `${r.model_code} · ${r.season} — ${r.article_code}`,
			meta: r.colorway + (r.rev_label ? ` · ${r.rev_label}` : ''),
			flags: flag ? [flag] : [],
		}, this.toCbd(r));
	},

	cbdModel() {
		const rows = q_worklist_cbd.data || [];
		const of = kind => rows.filter(r => r.kind === kind);
		const gaps = q_worklist_gap.data || [];
		const refreshFlag = r => ({
			text: r.refresh_reason === 'SPEC' ? 'Specsheet acuan sudah direvisi' : 'Harga master berubah', tone: 'warn',
		});
		return {
			subtitle: 'Pekerjaan CBD dan harga material yang perlu ditindaklanjuti.',
			stats: [
				{ key: 'to-create', value: of('TO_CREATE').length, label: 'CBD perlu dibuat', tone: 'info' },
				{ key: 'to-refresh', value: of('TO_REFRESH').length, label: 'Draft perlu refresh', tone: 'warn' },
				{ key: 'to-revise', value: of('TO_REVISE').length, label: 'CBD terbit perlu revisi', tone: 'warn' },
				{ key: 'price-gaps', value: gaps.length, label: 'Harga master belum ada', tone: 'warn' },
			],
			sections: [
				{
					key: 'to-create', title: 'CBD Perlu Dibuat', empty: 'Semua article aktif sudah punya CBD.',
					items: of('TO_CREATE').map(r => this.cbdItem(r, { text: 'Aktif di specsheet terbit', tone: 'muted' })),
				},
				{
					key: 'to-refresh', title: 'Draft CBD Perlu Refresh',
					empty: 'Tidak ada draft yang tertinggal dari specsheet atau master harga.',
					items: of('TO_REFRESH').map(r => this.cbdItem(r, refreshFlag(r))),
				},
				{
					key: 'to-revise', title: 'CBD Terbit Perlu Revisi', empty: 'Semua CBD terbit masih sesuai specsheet.',
					items: of('TO_REVISE').map(r => this.cbdItem(r, { text: 'PERLU REVISI', tone: 'warn' })),
				},
				{
					key: 'in-progress', title: 'Draft CBD Berjalan', hideWhenEmpty: true, empty: '',
					items: of('IN_PROGRESS').map(r => this.cbdItem(r, { text: 'DRAFT', tone: 'info' })),
				},
				{
					key: 'price-gaps', title: 'Harga Master Belum Ada',
					note: 'Material katalog + supplier yang dipakai di specsheet terbit tapi belum punya harga berlaku.',
					empty: 'Semua material yang dipakai sudah punya harga master.',
					items: gaps.map(g => Object.assign({
						title: `${g.material_code} · ${g.material_name}`,
						meta: `Supplier ${g.supplier_name} · dipakai di ${g.models}`,
						flags: [].concat(
							Number(g.color_count) > 0 ? [{ text: `${g.color_count} warna tanpa harga`, tone: 'warn', hint: g.colors }] : [],
							g.has_pending ? [{ text: 'Usulan harga menunggu approval', tone: 'info' }] : []
						),
					}, this.toMaterial(g))),
				},
			],
		};
	},

	// ---- Master Admin ----
	adminItem(r) {
		const nav = r.kind === 'COMPONENT' ? { target: 'Master Komponen', params: {} }
			: r.kind === 'SUPPLIER' ? { target: 'Master Supplier', params: {} } : this.toMaterial(r);
		const meta = [r.detail, r.amount_text, `diusulkan ${r.proposed_by || '-'}`, Util.fmtDateTime(r.proposed_at)]
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
			subtitle: 'Usulan yang menunggu persetujuan Anda.',
			stats: [
				{ key: 'appr-suppliers', value: of('SUPPLIER').length, label: 'Supplier usulan', tone: 'warn' },
				{ key: 'appr-materials', value: of('MATERIAL').length, label: 'Material usulan', tone: 'warn' },
				{ key: 'appr-components', value: of('COMPONENT').length, label: 'Komponen usulan', tone: 'warn' },
				{ key: 'appr-links', value: of('LINK').length, label: 'Supplier material usulan', tone: 'warn' },
				{ key: 'appr-prices', value: of('PRICE').length, label: 'Harga usulan', tone: 'warn' },
			],
			sections: [
				section('appr-suppliers', 'SUPPLIER', 'Supplier Menunggu Persetujuan', 'Tidak ada supplier usulan.',
					'Disetujui di halaman Master Supplier (Ubah → status APPROVED).'),
				section('appr-materials', 'MATERIAL', 'Material Menunggu Persetujuan', 'Tidak ada material usulan.'),
				section('appr-components', 'COMPONENT', 'Komponen Menunggu Persetujuan', 'Tidak ada komponen usulan.',
					'Disetujui di halaman Master Komponen.'),
				section('appr-links', 'LINK', 'Supplier Material Menunggu Persetujuan', 'Tidak ada supplier material usulan.',
					'Terbentuk otomatis saat tim specsheet memilih supplier di BOM.'),
				section('appr-prices', 'PRICE', 'Harga Menunggu Approval', 'Tidak ada usulan harga.',
					'Usulan Vendor CBD. Harga lama tetap berlaku sampai usulan disetujui.'),
			],
		};
	},

	// ---- Brand ----
	brandModel() {
		const specs = q_worklist_pub_spec.data || [];
		const cbds = q_worklist_pub_cbd.data || [];
		return {
			subtitle: 'Specsheet dan CBD yang baru diterbitkan.',
			columns: 2,
			sections: [
				{
					key: 'pub-spec', title: 'Specsheet Terbit Terbaru', note: 'Revisi terbit terakhir tiap season.',
					empty: 'Belum ada specsheet terbit.',
					items: specs.map(r => Object.assign({
						title: `${r.model_code} · ${r.season} — ${r.stage} r${r.revision_no}`,
						meta: `${r.model_name} · terbit ${Util.fmtDateTime(r.published_at)}`,
						flags: [],
					}, this.toSpec(r))),
				},
				{
					key: 'pub-cbd', title: 'CBD Terbit Terbaru', note: 'Revisi terbit terakhir tiap article.',
					empty: 'Belum ada CBD terbit.',
					items: cbds.map(r => Object.assign({
						title: `${r.model_code} · ${r.article_code} — ${r.stage} r${r.revision_no}`,
						meta: `${r.colorway} · terbit ${Util.fmtDateTime(r.published_at)}`,
						flags: r.sync_status === 'NEEDS_REVISION' ? [{ text: 'PERLU REVISI', tone: 'warn' }] : [],
					}, this.toCbd(r))),
				},
			],
		};
	},

	// ---- System Admin ----
	systemModel() {
		const s = (q_worklist_system.data && q_worklist_system.data[0]) || null;
		const n = v => Util.fmtNum(s ? v : 0);
		return {
			subtitle: 'Ringkasan sistem.',
			stats: s ? [
				{ key: 'sys', value: s.models, label: 'Model', tone: '' },
				{ key: 'sys', value: s.specsheets, label: 'Specsheet (season)', tone: '' },
				{ key: 'sys', value: s.cbd_revisions, label: 'Revisi CBD', tone: '' },
				{ key: 'sys', value: s.audit_entries, label: 'Entri audit log', tone: '' },
			] : [],
			sections: [{
				key: 'sys', title: 'Ringkasan Sistem', empty: 'Data ringkasan belum bisa dimuat.',
				items: s ? [{
					title: `${n(s.materials)} material · ${n(s.articles)} article · ${n(s.active_users)} user aktif`,
					meta: `Aktivitas terakhir ${Util.fmtDateTime(s.last_audit)}. Buka menu Admin untuk user dan audit log.`,
					target: 'Admin', params: {},
				}] : [],
			}],
		};
	},
}
