// JSObject "ModelCtrl" — page Model List. Form tambah: Custom Widget cwModelForm di modal mdlModel.
// Izin: lihat = view_model · tambah model = edit_model (Master Admin, Vendor – Specsheet) · tombol CBD = view_cbd.
// Semua dicek lagi di DB. Setelah model ditambah, langsung dibuka di Model Detail (isi season & article).
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

	openAdd() {
		this.form = {
			code: '', name: '', category: '', factory: '', outsole_mold: '', last_no: '',
			construction: '', size_range: '', sample_size: '',
		};
		this.busy = false;
		this.message = null;
		this.formKey = this.formKey + 1;
		showModal('mdlModel');
	},

	async save() {
		// Baca model dulu — model di-reset saat state (Default model) berubah
		const m = cwModelForm.model || {};
		const data = {
			code: m.code, name: m.name, category: m.category, factory: m.factory, outsole_mold: m.outsole_mold,
			last_no: m.last_no, construction: m.construction, size_range: m.size_range, sample_size: m.sample_size,
		};
		if (!data.code || !data.name) {
			this.message = { type: 'error', text: 'Kode dan nama model wajib diisi.' };
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
			this.message = { type: 'error', text: Util.cleanError(msg) };   // mis. kode model sudah dipakai
			return;
		} finally {
			this.busy = false;
		}
		closeModal('mdlModel');
		const id = a_model_add.data && a_model_add.data[0] && a_model_add.data[0].id;
		showAlert(`Model ${data.code} ditambahkan. Tambahkan season & article-nya.`, 'success');
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
