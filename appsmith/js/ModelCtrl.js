// JSObject "ModelCtrl" — page Model List. Form tambah: Custom Widget cwModelForm di modal mdlModel.
// Izin: lihat = view_model · tambah model = edit_model (Master Admin, Vendor – Specsheet) · tombol CBD = view_cbd.
// Semua dicek lagi di DB. Setelah model ditambah, langsung dibuka di Model Detail (isi season & article).
// R4: model tanpa kode (nama unik per pabrik), pilihan dari Master Pilihan (q_model_options). R6: Brand / System Admin
// memfilter per pabrik (selModelPabrik).
export default {
	form: {},
	formKey: 0,        // naik setiap modal dibuka -> cwModelForm mengisi ulang field
	busy: false,
	message: null,     // { type, text } ditampilkan di dalam cwModelForm

	canEdit() {
		return Auth.can('edit_model');
	},

	canViewCbd() {
		return Auth.can('view_cbd');
	},

	// R6: Brand / System Admin (tanpa pabrik) melihat semua pabrik -> filter pabrik
	canFilterFactory() {
		return !!Auth.me && !Auth.me.factory_id;
	},

	factoryOptions() {
		return [{ label: 'Semua pabrik', value: '' }].concat((q_model_factories.data || []).map(f => ({ label: f.name, value: f.id })));
	},

	// SS26 -> "SS26 · Spring/Summer 2026"
	seasonLabel(season) {
		const m = /^(SS|FH)(\d{2})$/.exec(season || '');
		if (!m) return season || '';
		return `${season} · ${m[1] === 'SS' ? 'Spring/Summer' : 'Fall/Holiday'} 20${m[2]}`;
	},

	seasonOptions() {
		return (q_known_seasons.data || []).map(r => ({ label: this.seasonLabel(r.season), value: r.season }));
	},

	// Kolom "Season" di tabel
	seasonSummary(row) {
		if (!row.season) return 'Belum ada season';
		const more = row.season_count > 1 ? ` (+${row.season_count - 1} season lain)` : '';
		return `${row.season} · ${row.article_count} article${more}`;
	},

	// Kolom "Specsheet": revisi terakhir season itu (P2). Role tanpa view_drafts (Brand) hanya revisi terbit.
	specSummary(row) {
		const drafts = Auth.can('view_drafts');
		const label = drafts ? row.spec_label : row.spec_label_pub;
		const n = drafts ? row.spec_active_articles : row.spec_active_articles_pub;
		if (!row.season) return '-';
		return label ? `${label} · ${n} article aktif` : 'Belum ada specsheet';
	},

	// ---- pilihan model (R4, q_model_options) ----
	// { KATEGORI: [{ value, label }], ... } — ACTIVE + nilai lama form (ditandai INACTIVE); sizes = UKURAN ACTIVE
	optionModel(form) {
		const rows = q_model_options.data || [];
		const cur = new Set(Object.values(form || {}).filter(v => typeof v === 'string' && v));
		const opts = {};
		['KATEGORI', 'GENDER', 'CONSTRUCTION', 'LAST', 'OUTSOLE_MOLD'].forEach(k => {
			opts[k] = rows.filter(r => r.kind === k && (r.status === 'ACTIVE' || cur.has(r.id)))
				.map(r => ({ value: r.id, label: r.status === 'ACTIVE' ? r.value : `${r.value} (INACTIVE)` }));
		});
		const sizes = rows.filter(r => r.kind === 'UKURAN' && r.status === 'ACTIVE').map(r => Number(r.value)).filter(n => n > 0);
		return { options: opts, sizes };
	},

	// Isi cwModelForm -> parameter query simpan model (fn_model_save; sizes dikirim sebagai JSON)
	modelParams(f) {
		return {
			name: String(f.name || '').trim(), category_id: f.category_id || '', construction_id: f.construction_id || '',
			gender_id: f.gender_id || '', last_id: f.last_id || '', outsole_mold_id: f.outsole_mold_id || '',
			sizes: JSON.stringify(Array.isArray(f.sizes) ? f.sizes : []),
			sample_size: f.sample_size === null || f.sample_size === undefined ? '' : String(f.sample_size),
		};
	},

	// Default model cwModelForm
	formModel() {
		return Object.assign({
			key: this.formKey, mode: 'add', form: this.form, busy: this.busy, message: this.message,
		}, this.optionModel(this.form));
	},

	async openAdd() {
		try { await q_model_options.run(); } catch (e) { /* daftar lama tetap dipakai */ }
		this.form = {
			name: '', category_id: '', gender_id: '', construction_id: '', last_id: '', outsole_mold_id: '',
			sizes: [], sample_size: null,
		};
		this.busy = false;
		this.message = null;
		this.formKey = this.formKey + 1;
		showModal('mdlModel');
	},

	async save() {
		// Baca model dulu — model di-reset saat state (Default model) berubah
		const m = cwModelForm.model || {};
		const data = this.modelParams(m);
		if (!data.name || !data.category_id) {
			this.message = { type: 'error', text: 'Nama model dan kategori wajib diisi.' };
			return;
		}
		this.message = null;
		this.busy = true;
		try {
			await a_model_add.run(data);
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlModel');
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };   // mis. nama model sudah ada
			return;
		} finally {
			this.busy = false;
		}
		closeModal('mdlModel');
		const id = a_model_add.data && a_model_add.data[0] && a_model_add.data[0].id;
		showAlert(`Model ${data.name.toUpperCase()} ditambahkan. Tambahkan season & article-nya.`, 'success');
		if (id) navigateTo('Model Detail', { id });
	},

	open(row) {
		navigateTo('Model Detail', row.specsheet_id ? { id: row.id, season: row.specsheet_id } : { id: row.id });
	},

	// from: 'list' -> tombol kembali di Specsheet / CBD mengarah ke Model List
	openSpecsheet(row) {
		navigateTo('Specsheet', row.specsheet_id ? { model_id: row.id, season: row.specsheet_id, from: 'list' } : { model_id: row.id, from: 'list' });
	},

	openCbd(row) {
		navigateTo('Cost Breakdown (CBD)', row.specsheet_id ? { model_id: row.id, season: row.specsheet_id, from: 'list' } : { model_id: row.id, from: 'list' });
	},
}
