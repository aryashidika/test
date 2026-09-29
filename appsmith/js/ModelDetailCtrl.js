// JSObject "ModelDetailCtrl" — page Model Detail (?id=<model id>&season=<specsheet id, opsional>).
// Form: cwModelForm (mdlModel), cwSeasonForm (mdlSeason), cwArticleForm (mdlArticle).
// Lampiran article: modal mdlLampiran (FilePicker + tabel + pratinjau gambar).
// Izin: lihat = view_model · ubah model, season, article, lampiran = edit_model. Semua dicek lagi di DB
// (maks. 5 article per season, kode article yang sudah dipakai terkunci, jenis & ukuran lampiran).
// Query q_articles & q_attachments selalu dijalankan lewat loadArticles() / loadAttachments() (pakai params).
export default {
	seasonId: '',          // season (specsheet) yang dipilih di selSeason
	article: null,         // article yang lampirannya sedang dibuka di mdlLampiran
	preview: null,         // { id, name, url } gambar yang sedang ditampilkan
	fileBusy: false,

	modelKey: 0, modelBusy: false, modelMsg: null,
	seasonKey: 0, seasonBusy: false, seasonMsg: null,
	articleKey: 0, articleBusy: false, articleMsg: null, articleIsNew: true, articleForm: {},

	MAX_ARTICLES: 5,
	MAX_BYTES: 5 * 1024 * 1024,

	// ---- data ----
	model() {
		return (q_model.data && q_model.data[0]) || null;
	},

	seasons() {
		return q_seasons.data || [];
	},

	season() {
		return this.seasons().find(s => s.id === this.seasonId) || null;
	},

	articles() {
		return q_articles.data || [];
	},

	attachments() {
		return q_attachments.data || [];
	},

	// ---- izin (tampilan saja) ----
	canEdit() { return Auth.can('edit_model'); },
	canViewCbd() { return Auth.can('view_cbd'); },
	canAddArticle() { return this.canEdit() && !!this.seasonId && this.articles().length < this.MAX_ARTICLES; },

	// ---- label & teks ----
	esc(v) {
		return String(v ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
	},

	seasonLabel(season) {
		const m = /^(SS|FH)(\d{2})$/.exec(season || '');
		if (!m) return season || '';
		return `${season} · ${m[1] === 'SS' ? 'Spring/Summer' : 'Fall/Holiday'} 20${m[2]}`;
	},

	seasonOptions() {
		return this.seasons().map(s => ({ label: `${this.seasonLabel(s.season)} (${s.article_count} article)`, value: s.id }));
	},

	headerText() {
		const m = this.model();
		if (!m) return q_model.isLoading ? 'Memuat…' : 'Model tidak ditemukan. Buka dari Model List.';
		const e = v => this.esc(v);
		return `<b style="font-size:18px">${e(m.code)} — ${e(m.name)}</b><br>`
			+ `Kategori: ${e(m.category || '-')} · Factory: ${e(m.factory || '-')} · ${this.seasons().length} season`;
	},

	infoText() {
		const m = this.model();
		if (!m) return '';
		const rows = [
			['Kode Model', m.code], ['Nama Model', m.name], ['Kategori', m.category], ['Factory', m.factory],
			['Outsole Mould', m.outsole_mold], ['Last No.', m.last_no], ['Construction', m.construction],
			['Size Range', m.size_range], ['Sample Size', m.sample_size],
		];
		return '<table style="border-collapse:collapse">' + rows.map(([k, v]) =>
			`<tr><td style="padding:4px 24px 4px 0;color:#6b7280">${k}</td><td style="padding:4px 0"><b>${this.esc(v || '-')}</b></td></tr>`
		).join('') + '</table>'
			+ `<div style="margin-top:12px;color:#6b7280;font-size:12px">Diubah ${Util.fmtDateTime(m.updated_at)} oleh ${this.esc(m.updated_by || '-')}</div>`;
	},

	articleNote() {
		if (!this.seasonId) {
			return this.seasons().length ? '' : (this.canEdit()
				? 'Belum ada season. Klik "+ Season Baru", lalu isi article/colorway-nya di sini sebelum membuat specsheet.'
				: 'Belum ada season.');
		}
		const n = this.articles().length;
		let t = `${n} dari maks. ${this.MAX_ARTICLES} article di season ${this.season() ? this.season().season : ''}.`;
		if (this.canEdit() && n) {
			t += ' Article yang sudah dipakai di specsheet/CBD tidak bisa dihapus dan kodenya tidak bisa diubah — hentikan pemakaiannya dengan drop di specsheet.';
		}
		return t;
	},

	attachmentTitle() {
		const a = this.article;
		return a ? `Lampiran — ${this.esc(a.code)} · ${this.esc(a.colorway)}` : 'Lampiran';
	},

	fmtSize(bytes) {
		if (!bytes && bytes !== 0) return '-';
		return bytes >= 1048576 ? `${(bytes / 1048576).toFixed(1).replace('.', ',')} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
	},

	fileType(mime) {
		return { 'image/jpeg': 'JPG', 'image/png': 'PNG', 'application/pdf': 'PDF' }[mime] || mime;
	},

	// ---- muat data ----
	// Dipanggil Auth.pageQueries() setelah q_model & q_seasons.
	async init() {
		const want = this.seasonId || appsmith.URL.queryParams.season;
		const list = this.seasons();
		const found = list.find(s => s.id === want);
		this.seasonId = found ? found.id : (list[0] ? list[0].id : '');   // q_seasons: season terbaru dulu
		await this.loadArticles();
	},

	async loadArticles() {
		try {
			await q_articles.run({ specsheet_id: this.seasonId || '' });
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
	},

	async loadAttachments() {
		try {
			await q_attachments.run({ article_id: (this.article && this.article.id) || '' });
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
	},

	async pickSeason(id) {
		this.seasonId = id || '';
		await this.loadArticles();
	},

	async refresh(queries) {
		for (const q of queries) {
			try { await q.run(); } catch (e) { /* abaikan */ }
		}
	},

	// ---- helper simpan dari form Custom Widget ----
	async runForm(query, params, setMsg, setBusy, modal) {
		setMsg(null);
		setBusy(true);
		try {
			await query.run(params);
			return true;
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal(modal);
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return false;
			}
			setMsg({ type: 'error', text: Util.cleanError(msg) });
			return false;
		} finally {
			setBusy(false);
		}
	},

	// ---- navigasi ----
	openSpecsheet() {
		const m = this.model();
		if (m) navigateTo('Specsheet', this.seasonId ? { model_id: m.id, season: this.seasonId } : { model_id: m.id });
	},

	openCbd() {
		const m = this.model();
		if (m) navigateTo('Cost Breakdown (CBD)', this.seasonId ? { model_id: m.id, season: this.seasonId } : { model_id: m.id });
	},

	// ---- model ----
	openEditModel() {
		this.modelBusy = false;
		this.modelMsg = null;
		this.modelKey = this.modelKey + 1;
		showModal('mdlModel');
	},

	modelFormModel() {
		const m = this.model() || {};
		return {
			key: this.modelKey,
			mode: 'edit',
			form: {
				code: m.code, name: m.name, category: m.category, factory: m.factory, outsole_mold: m.outsole_mold,
				last_no: m.last_no, construction: m.construction, size_range: m.size_range, sample_size: m.sample_size,
			},
			busy: this.modelBusy,
			message: this.modelMsg,
		};
	},

	async saveModel() {
		const f = cwModelForm.model || {};
		const params = {
			id: appsmith.URL.queryParams.id, code: f.code, name: f.name, category: f.category, factory: f.factory,
			outsole_mold: f.outsole_mold, last_no: f.last_no, construction: f.construction,
			size_range: f.size_range, sample_size: f.sample_size,
		};
		const ok = await this.runForm(a_model_update, params,
			v => { this.modelMsg = v; }, v => { this.modelBusy = v; }, 'mdlModel');
		if (!ok) return;
		closeModal('mdlModel');
		showAlert('Model disimpan.', 'success');
		await this.refresh([q_model]);
	},

	// ---- season ----
	openAddSeason() {
		this.seasonBusy = false;
		this.seasonMsg = null;
		this.seasonKey = this.seasonKey + 1;
		showModal('mdlSeason');
	},

	seasonFormModel() {
		return {
			key: this.seasonKey,
			existing: this.seasons().map(s => s.season),
			busy: this.seasonBusy,
			message: this.seasonMsg,
		};
	},

	async saveSeason() {
		const f = cwSeasonForm.model || {};
		const ok = await this.runForm(a_season_add, { model_id: appsmith.URL.queryParams.id, season: f.season },
			v => { this.seasonMsg = v; }, v => { this.seasonBusy = v; }, 'mdlSeason');
		if (!ok) return;
		closeModal('mdlSeason');
		const id = a_season_add.data && a_season_add.data[0] && a_season_add.data[0].id;
		showAlert(`Season ${f.season} ditambahkan.`, 'success');
		await this.refresh([q_seasons]);
		await this.pickSeason(id || this.seasonId);
	},

	// ---- article ----
	openAddArticle() {
		this.articleIsNew = true;
		this.articleForm = { id: null, code: '', colorway: '', is_used: false };
		this.articleBusy = false;
		this.articleMsg = null;
		this.articleKey = this.articleKey + 1;
		showModal('mdlArticle');
	},

	openEditArticle(row) {
		this.articleIsNew = false;
		this.articleForm = { id: row.id, code: row.code, colorway: row.colorway, is_used: !!row.is_used };
		this.articleBusy = false;
		this.articleMsg = null;
		this.articleKey = this.articleKey + 1;
		showModal('mdlArticle');
	},

	articleFormModel() {
		const s = this.season();
		return {
			key: this.articleKey,
			mode: this.articleIsNew ? 'add' : 'edit',
			season: s ? s.season : '',
			count: this.articles().length,
			max: this.MAX_ARTICLES,
			form: { code: this.articleForm.code, colorway: this.articleForm.colorway },
			codeLocked: !!this.articleForm.is_used,
			busy: this.articleBusy,
			message: this.articleMsg,
		};
	},

	async saveArticle() {
		const f = cwArticleForm.model || {};
		const isNew = this.articleIsNew;
		const query = isNew ? a_article_add : a_article_update;
		const params = isNew
			? { specsheet_id: this.seasonId, code: f.code, colorway: f.colorway }
			: { id: this.articleForm.id, code: f.code, colorway: f.colorway };
		const ok = await this.runForm(query, params,
			v => { this.articleMsg = v; }, v => { this.articleBusy = v; }, 'mdlArticle');
		if (!ok) return;
		closeModal('mdlArticle');
		showAlert(isNew ? `Article ${f.code} ditambahkan.` : 'Article disimpan.', 'success');
		await this.loadArticles();
		await this.refresh([q_seasons]);
	},

	async deleteArticle(row) {
		if (!await Util.run(a_article_delete, { id: row.id }, `Article ${row.code} dihapus.`)) return;
		await this.loadArticles();
		await this.refresh([q_seasons]);
	},

	// ---- lampiran ----
	async openAttachments(row) {
		this.article = row;
		this.preview = null;
		resetWidget('fpLampiran');
		resetWidget('inpLampiranCatatan');
		showModal('mdlLampiran');
		await this.loadAttachments();
	},

	async upload() {
		const file = fpLampiran.files && fpLampiran.files[0];
		if (!file || !this.article) return;
		if (file.size > this.MAX_BYTES) {
			showAlert(`Ukuran file ${this.fmtSize(file.size)}, maksimal 5 MB.`, 'error');
			resetWidget('fpLampiran');
			return;
		}
		this.fileBusy = true;
		const ok = await Util.run(a_attachment_add, {
			article_id: this.article.id, file_name: file.name, b64: file.data, note: inpLampiranCatatan.text || '',
		}, `Lampiran ${file.name} diunggah.`);
		this.fileBusy = false;
		resetWidget('fpLampiran');
		if (!ok) return;
		resetWidget('inpLampiranCatatan');
		await this.loadAttachments();
		await this.loadArticles();
	},

	async fetchFile(row) {
		try {
			await q_attachment_file.run({ id: row.id });
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
			return null;
		}
		const f = q_attachment_file.data && q_attachment_file.data[0];
		return f ? { name: f.file_name, mime: f.mime_type, url: `data:${f.mime_type};base64,${f.b64}` } : null;
	},

	// Gambar -> pratinjau di modal; PDF -> diunduh
	async view(row) {
		if (row.mime_type === 'application/pdf') return this.download(row);
		const f = await this.fetchFile(row);
		if (f) this.preview = { id: row.id, name: f.name, url: f.url };
	},

	async download(row) {
		const f = await this.fetchFile(row);
		if (f) download(f.url, f.name, f.mime);
	},

	async deleteAttachment(row) {
		if (!await Util.run(a_attachment_delete, { id: row.id }, `Lampiran ${row.file_name} dihapus.`)) return;
		if (this.preview && this.preview.id === row.id) this.preview = null;
		await this.loadAttachments();
		await this.loadArticles();
	},
}
