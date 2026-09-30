// JSObject "SpecCtrl" — page Specsheet (?model_id=<model id>&season=<specsheet id>, keduanya opsional).
// Dibuka dari Model List / Model Detail -> model & season langsung terpilih; dari sidebar -> pilih dulu
// di selSpecModel lalu selSpecSeason. Stepper revisi (cwStepper), Buat Revisi (cwRevisionForm di mdlRevisi), Hapus Draft.
// Grid BOM & article revisi ada di BomCtrl. Izin: lihat = view_specsheet (Brand hanya revisi terbit — difilter
// query) · ubah = edit_specsheet (Vendor – Specsheet). Semua dicek lagi di DB.
// Query q_spec_model, q_spec_seasons, q_revisions dijalankan dengan params (loadModel / loadSeason);
// isi revisi lewat BomCtrl.load().
export default {
	modelId: '',       // model yang dipilih
	from: '',          // asal halaman (?from=list | detail) -> tujuan tombol kembali
	seasonId: '',      // specsheet (season) yang dipilih
	revisionId: '',    // revisi yang dibuka
	firstLoad: true,

	revKey: 0, revBusy: false, revMsg: null,

	STAGES: ['PULL', 'SMS', 'GTM', 'PROD'],

	// ---- data ----
	models() {
		return q_spec_models.data || [];
	},

	model() {
		return (q_spec_model.data && q_spec_model.data[0]) || null;
	},

	seasons() {
		return q_spec_seasons.data || [];
	},

	season() {
		return this.seasons().find(s => s.id === this.seasonId) || null;
	},

	revisions() {
		return q_revisions.data || [];
	},

	revision() {
		return this.revisions().find(r => r.id === this.revisionId) || null;
	},

	draft() {
		return this.revisions().find(r => r.status === 'DRAFT') || null;
	},

	// Revisi terbit terakhir: urut stage lalu nomor revisi (P1)
	latestPublished() {
		const pub = this.revisions().filter(r => r.status === 'PUBLISHED');
		pub.sort((a, b) => (b.stage_order - a.stage_order) || (b.revision_no - a.revision_no));
		return pub[0] || null;
	},

	label(r) {
		return r ? `${r.stage} r${r.revision_no}` : '';
	},

	// ---- izin (tampilan saja) ----
	canEdit() { return Auth.can('edit_specsheet'); },
	canViewCbd() { return Auth.can('view_cbd'); },
	editable() {
		const r = this.revision();
		return this.canEdit() && !!r && r.status === 'DRAFT';
	},
	canCreate() {
		return this.canEdit() && !!this.seasonId && !this.draft();
	},

	// ---- muat data ----
	// Dipanggil Auth.pageQueries(). Model & season dari URL (dari Model List / Model Detail) kalau ada.
	async init() {
		try {
			await q_spec_models.run();
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
		const url = appsmith.URL.queryParams;
		if (this.firstLoad) this.from = url.from || '';
		const want = this.modelId || (this.firstLoad ? url.model_id : '');
		this.modelId = this.models().some(m => m.id === want) ? want : '';
		if (want && !this.modelId) showAlert('Model tidak ditemukan. Pilih model di atas.', 'warning');
		await this.loadModel(this.firstLoad ? url.season : this.seasonId);
		this.firstLoad = false;
	},

	// Muat model + season-nya, pilih season (wantSeason atau season terbaru), lalu revisi.
	async loadModel(wantSeason) {
		try {
			await Promise.all([
				q_spec_model.run({ model_id: this.modelId || '' }),
				q_spec_seasons.run({ model_id: this.modelId || '' }),
			]);
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
		const list = this.seasons();
		const found = list.find(s => s.id === wantSeason);
		this.seasonId = found ? found.id : (list[0] ? list[0].id : '');   // q_spec_seasons: season terbaru dulu
		this.revisionId = '';
		await this.loadSeason();
	},

	async pickModel(id) {
		this.modelId = id || '';
		await this.loadModel('');
	},

	// Muat revisi season ini lalu buka revisi: pickId, revisi yang sedang dibuka, draft, atau terbit terakhir.
	async loadSeason(pickId) {
		try {
			await q_revisions.run({ specsheet_id: this.seasonId || '' });
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
		const revs = this.revisions();
		const keep = revs.find(r => r.id === (pickId || this.revisionId));
		const pick = keep || this.draft() || this.latestPublished() || revs[revs.length - 1] || null;
		this.revisionId = pick ? pick.id : '';
		await BomCtrl.load();
	},

	async pickSeason(id) {
		this.seasonId = id || '';
		this.revisionId = '';
		await this.loadSeason();
	},

	// cwStepper onSelect
	async selectRevision() {
		const id = (cwStepper.model || {}).selectedId;
		if (!id || id === this.revisionId) return;
		this.revisionId = id;
		await BomCtrl.load();
	},

	async refreshSeasons() {
		try { await q_spec_seasons.run({ model_id: this.modelId || '' }); } catch (e) { /* abaikan */ }
	},

	// ---- tampilan ----
	esc(v) {
		return String(v ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
	},

	modelOptions() {
		return this.models().map(m => ({ label: `${m.code} — ${m.name}`, value: m.id }));
	},

	seasonOptions() {
		return this.seasons().map(s => ({ label: `${s.season} (${s.revision_count} revisi)`, value: s.id }));
	},

	headerText() {
		const m = this.model();
		if (!m) return this.modelId && q_spec_model.isLoading ? 'Memuat…' : 'Pilih model dan season dahulu.';
		const e = v => this.esc(v || '-');
		return `<b style="font-size:18px">${e(m.code)} — ${e(m.name)}</b><br>`
			+ `<span style="color:#6b7280">Kategori: ${e(m.category)} · Factory: ${e(m.factory)} · Outsole Mould: ${e(m.outsole_mold)}`
			+ ` · Last No.: ${e(m.last_no)} · Construction: ${e(m.construction)} · Size Range: ${e(m.size_range)}`
			+ ` · Sample Size: ${e(m.sample_size)}</span>`;
	},

	stepperModel() {
		return {
			revisions: this.revisions().map(r => ({ id: r.id, stage: r.stage, revision_no: r.revision_no, status: r.status })),
			selectedId: this.revisionId,
			emptyText: !this.modelId ? 'Pilih model dulu.'
				: !this.seasonId ? 'Model ini belum punya season.'
				: (this.canEdit() ? 'Belum ada revisi. Klik "+ Buat Revisi".' : 'Belum ada revisi yang terbit.'),
		};
	},

	revisionText() {
		const r = this.revision();
		const s = this.season();
		if (!this.modelId) return '';
		if (!this.seasonId) {
			return 'Model ini belum punya season. Tambahkan season & article di halaman Model Detail.';
		}
		if (!r) return '';
		const e = v => this.esc(v);
		let t = `<b>${e(s ? s.season : '')} · ${e(this.label(r))}</b> · `
			+ `<b style="color:${Util.statusColor(r.status)}">${r.status}</b>`;
		if (r.status === 'PUBLISHED') t += ` · terbit ${Util.fmtDateTime(r.published_at)} oleh ${e(r.published_by || '-')}`;
		else t += ` · dibuat ${Util.fmtDateTime(r.created_at)} oleh ${e(r.created_by || '-')}`;
		if (r.source_label) t += ` · sumber: ${e(r.source_season)} ${e(r.source_label)}`;
		if (this.canEdit() && r.status === 'PUBLISHED' && this.draft()) {
			t += ` · <span style="color:#d97706">ada draft ${e(this.label(this.draft()))}</span>`;
		}
		return t;
	},

	// ---- navigasi ----
	// Tombol kembali: ke page asal (Model List / Model Detail). Dibuka dari sidebar: Model Detail kalau model
	// sudah dipilih, kalau belum Model List.
	backToList() {
		return this.from === 'list' || !this.model();
	},

	backLabel() {
		return this.backToList() ? '← Model List' : '← Model Detail';
	},

	openModel() {
		const m = this.model();
		if (this.backToList()) return navigateTo('Model List');
		navigateTo('Model Detail', this.seasonId ? { id: m.id, season: this.seasonId } : { id: m.id });
	},

	openCbd() {
		const m = this.model();
		if (m) navigateTo('Cost Breakdown (CBD)', this.seasonId ? { model_id: m.id, season: this.seasonId } : { model_id: m.id });
	},

	// ---- buat revisi ----
	openCreate() {
		this.revBusy = false;
		this.revMsg = null;
		this.revKey = this.revKey + 1;
		showModal('mdlRevisi');
	},

	revisionFormModel() {
		const latest = this.latestPublished();
		const revs = this.revisions();
		let nextRevision = '';
		let nextStage = null;
		if (latest) {
			const maxNo = Math.max(...revs.filter(r => r.stage === latest.stage).map(r => r.revision_no));
			nextRevision = `${latest.stage} r${maxNo + 1}`;
			const i = this.STAGES.indexOf(latest.stage);
			nextStage = i < this.STAGES.length - 1 ? `${this.STAGES[i + 1]} r0` : null;
		}
		const s = this.season();
		return {
			key: this.revKey,
			season: s ? s.season : '',
			hasRevisions: revs.length > 0,
			latestLabel: latest ? this.label(latest) : null,
			nextRevisionLabel: nextRevision,
			nextStageLabel: nextStage,
			copySources: this.seasons().filter(x => x.id !== this.seasonId && x.latest_pub_id)
				.map(x => ({ id: x.id, season: x.season, label: x.latest_pub_label })),
			busy: this.revBusy,
			message: this.revMsg,
		};
	},

	async saveRevision() {
		const f = cwRevisionForm.model || {};
		this.revMsg = null;
		this.revBusy = true;
		try {
			await a_revision_create.run({
				specsheet_id: this.seasonId, mode: f.mode, stage: f.stage || '', source_id: f.source_specsheet_id || '',
			});
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlRevisi');
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return;
			}
			this.revMsg = { type: 'error', text: Util.cleanError(msg) };
			return;
		} finally {
			this.revBusy = false;
		}
		closeModal('mdlRevisi');
		const id = a_revision_create.data && a_revision_create.data[0] && a_revision_create.data[0].id;
		showAlert('Revisi draft dibuat.', 'success');
		await this.refreshSeasons();
		await this.loadSeason(id);
	},

	// Query a_revision_delete memakai "Request confirmation before running" = ON
	async deleteDraft() {
		const r = this.revision();
		if (!r || r.status !== 'DRAFT') return;
		if (!await Util.run(a_revision_delete, { id: r.id }, `Draft ${this.label(r)} dihapus.`)) return;
		this.revisionId = '';
		await this.refreshSeasons();
		await this.loadSeason();
	},
}
