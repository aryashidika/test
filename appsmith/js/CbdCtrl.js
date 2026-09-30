// JSObject "CbdCtrl" — page Cost Breakdown (CBD) (?model_id=<model id>&season=<specsheet id>&from=list|detail, semua opsional).
// Dibuka dari Model List / Model Detail / Specsheet -> model & season langsung terpilih; dari sidebar -> pilih dulu
// di selCbdModel lalu selCbdSeason. Chip article + stepper revisi CBD (cwStepper), Buat CBD (cwCbdForm di mdlCbdBaru),
// Hapus Draft. Grid baris ada di CbdGridCtrl. Izin: lihat = view_cbd (Brand hanya revisi terbit — difilter query)
// · ubah = edit_cbd (Vendor – CBD). Semua dicek lagi di DB.
// CBD per article; acuan = revisi specsheet terbit terakhir season itu (article harus ACTIVE di sana).
export default {
	modelId: '',       // model yang dipilih
	from: '',          // asal halaman (?from=list | detail) -> tujuan tombol kembali
	seasonId: '',      // specsheet (season) yang dipilih
	articleId: '',     // article yang dipilih (chip)
	revisionId: '',    // revisi CBD yang dibuka
	firstLoad: true,

	createKey: 0, createBusy: false, createMsg: null,

	STAGES: ['PULL', 'SMS', 'GTM', 'PROD'],

	// ---- data ----
	models() {
		return q_cbd_models.data || [];
	},

	model() {
		return (q_cbd_model.data && q_cbd_model.data[0]) || null;
	},

	seasons() {
		return q_cbd_seasons.data || [];
	},

	season() {
		return this.seasons().find(s => s.id === this.seasonId) || null;
	},

	articles() {
		return q_cbd_articles.data || [];
	},

	article() {
		return this.articles().find(a => a.id === this.articleId) || null;
	},

	revisions() {
		return q_cbd_revisions.data || [];
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
	canEdit() { return Auth.can('edit_cbd'); },
	canViewSpec() { return Auth.can('view_specsheet'); },
	articleActive() {
		const a = this.article();
		return !!a && a.spec_status === 'ACTIVE';
	},
	editable() {
		const r = this.revision();
		return this.canEdit() && !!r && r.status === 'DRAFT' && this.articleActive();
	},
	canCreate() {
		return this.canEdit() && this.articleActive() && !this.draft();
	},
	canDeleteDraft() {
		const r = this.revision();
		return this.canEdit() && !!r && r.status === 'DRAFT';
	},

	// ---- muat data ----
	// Dipanggil Auth.pageQueries(). Model & season dari URL kalau ada.
	async init() {
		try {
			await q_cbd_models.run();
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

	// Muat model + season-nya, pilih season (wantSeason atau season terbaru), lalu article.
	async loadModel(wantSeason) {
		try {
			await Promise.all([
				q_cbd_model.run({ model_id: this.modelId || '' }),
				q_cbd_seasons.run({ model_id: this.modelId || '' }),
			]);
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
		const list = this.seasons();
		const found = list.find(s => s.id === wantSeason);
		this.seasonId = found ? found.id : (list[0] ? list[0].id : '');   // q_cbd_seasons: season terbaru dulu
		this.articleId = '';
		await this.loadSeason();
	},

	async pickModel(id) {
		this.modelId = id || '';
		await this.loadModel('');
	},

	// Muat article season ini lalu pilih: pickId, article yang sedang dibuka, atau article aktif pertama.
	async loadSeason(pickId) {
		try {
			await q_cbd_articles.run({ specsheet_id: this.seasonId || '' });
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
		const arts = this.articles();
		const keep = arts.find(a => a.id === (pickId || this.articleId));
		const pick = keep || arts.find(a => a.spec_status === 'ACTIVE') || arts[0] || null;
		this.articleId = pick ? pick.id : '';
		this.revisionId = keep ? this.revisionId : '';
		await this.loadArticle();
	},

	async pickSeason(id) {
		this.seasonId = id || '';
		this.articleId = '';
		this.revisionId = '';
		await this.loadSeason();
	},

	// Muat revisi CBD article ini lalu buka: pickId, revisi yang sedang dibuka, draft, atau terbit terakhir.
	async loadArticle(pickId) {
		try {
			await q_cbd_revisions.run({ article_id: this.articleId || '' });
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
		const revs = this.revisions();
		const keep = revs.find(r => r.id === (pickId || this.revisionId));
		const pick = keep || this.draft() || this.latestPublished() || revs[revs.length - 1] || null;
		this.revisionId = pick ? pick.id : '';
		await CbdGridCtrl.load();
	},

	// cwStepper onArticle
	async selectArticle() {
		const id = (cwStepper.model || {}).selectedArticleId;
		if (!id || id === this.articleId) return;
		this.articleId = id;
		this.revisionId = '';
		await this.loadArticle();
	},

	// cwStepper onSelect
	async selectRevision() {
		const id = (cwStepper.model || {}).selectedId;
		if (!id || id === this.revisionId) return;
		this.revisionId = id;
		await CbdGridCtrl.load();
	},

	// Setelah buat / hapus: status chip & revisi dimuat ulang
	async refresh(pickRevisionId) {
		try { await q_cbd_articles.run({ specsheet_id: this.seasonId || '' }); } catch (e) { /* abaikan */ }
		this.revisionId = pickRevisionId || '';
		await this.loadArticle(pickRevisionId);
	},

	// ---- tampilan ----
	esc(v) {
		return String(v ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
	},

	modelOptions() {
		return this.models().map(m => ({ label: `${m.code} — ${m.name}`, value: m.id }));
	},

	seasonOptions() {
		return this.seasons().map(s => ({
			label: `${s.season} (${s.spec_pub_label ? 'specsheet ' + s.spec_pub_label : 'specsheet belum terbit'})`, value: s.id,
		}));
	},

	headerText() {
		const m = this.model();
		if (!m) return this.modelId && q_cbd_model.isLoading ? 'Memuat…' : 'Pilih model dan season dahulu.';
		const e = v => this.esc(v || '-');
		return `<b style="font-size:18px">${e(m.code)} — ${e(m.name)}</b><br>`
			+ `<span style="color:#6b7280">Kategori: ${e(m.category)} · Factory: ${e(m.factory)} · Size Range: ${e(m.size_range)}`
			+ ` · Sample Size: ${e(m.sample_size)}</span>`;
	},

	// Chip article: status CBD (Brand hanya melihat terbit — draft_* kosong dari query)
	chip(a) {
		if (a.spec_status === 'DROPPED') return { badge: a.pub_label ? `DI-DROP · ${a.pub_label}` : 'DI-DROP', tone: 'muted' };
		if (a.draft_id) return { badge: `DRAFT ${a.draft_label}${a.draft_stale ? ' · specsheet baru' : ''}`, tone: 'draft' };
		if (a.pub_id && a.pub_sync === 'NEEDS_REVISION') return { badge: `PERLU REVISI · ${a.pub_label}`, tone: 'danger' };
		if (a.pub_id) return { badge: `TERBIT ${a.pub_label}`, tone: 'ok' };
		if (a.spec_status === 'NOT_PUBLISHED') return { badge: 'SPECSHEET BELUM TERBIT', tone: 'muted' };
		return { badge: 'BELUM ADA CBD', tone: 'info' };
	},

	stepperModel() {
		return {
			articles: this.articles().map(a => Object.assign({ id: a.id, code: a.code, colorway: a.colorway }, this.chip(a))),
			selectedArticleId: this.articleId,
			articleEmptyText: !this.modelId ? 'Pilih model dulu.'
				: !this.seasonId ? 'Model ini belum punya season.' : 'Belum ada article di season ini.',
			revisions: this.revisions().map(r => ({
				id: r.id, stage: r.stage, revision_no: r.revision_no, status: r.status,
				needsRevision: r.status === 'PUBLISHED' && r.sync_status === 'NEEDS_REVISION',
			})),
			selectedId: this.revisionId,
			emptyText: !this.articleId ? '' : (this.canCreate() ? 'Belum ada CBD. Klik "+ Buat CBD".' : 'Belum ada CBD yang terbit.'),
		};
	},

	// Info di bawah stepper: revisi yang dibuka + peringatan status article
	revisionText() {
		const a = this.article();
		const r = this.revision();
		if (!this.seasonId || !a) return '';
		const e = v => this.esc(v);
		let t = '';
		if (a.spec_status === 'DROPPED') {
			t += `<span style="color:#6b7280">Article ${e(a.code)} sudah di-drop di specsheet terbit terakhir — CBD hanya bisa dilihat.</span><br>`;
		} else if (a.spec_status === 'NOT_PUBLISHED') {
			t += `<span style="color:#6b7280">Article ${e(a.code)} belum ada di revisi specsheet yang terbit — terbitkan specsheet dulu.</span><br>`;
		}
		if (!r) return t;
		t += `<b>${e(a.code)} · ${e(a.colorway)} · ${e(this.label(r))}</b> · `
			+ `<b style="color:${Util.statusColor(r.status)}">${r.status}</b>`;
		if (r.status === 'PUBLISHED') {
			t += ` · <b style="color:${Util.statusColor(r.sync_status)}">${r.sync_status}</b>`;
			t += ` · terbit ${Util.fmtDateTime(r.published_at)} oleh ${e(r.published_by || '-')}`;
		} else {
			t += ` · dibuat ${Util.fmtDateTime(r.created_at)} oleh ${e(r.created_by || '-')}`;
		}
		t += ` · acuan specsheet ${e(r.spec_label)}`;
		if (r.source_label) t += ` · sumber: ${e(r.source_season)} / ${e(r.source_article)} / ${e(r.source_label)}`;
		if (r.status === 'DRAFT' && a.draft_stale) {
			t += `<br><span style="color:#dc2626">Specsheet sudah terbit ${e(a.spec_pub_label)} — baris draft ini masih memakai ${e(r.spec_label)}. Refresh dari specsheet tersedia di F8; sementara hapus draft lalu buat ulang.</span>`;
		}
		return t;
	},

	// ---- navigasi ----
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

	openSpec() {
		const m = this.model();
		if (!m) return;
		const p = { model_id: m.id };
		if (this.seasonId) p.season = this.seasonId;
		if (this.from) p.from = this.from;
		navigateTo('Specsheet', p);
	},

	// ---- buat CBD ----
	async openCreate() {
		const a = this.article();
		if (!a) return;
		if (!this.revisions().length) {
			try {
				await q_cbd_sources.run({ model_id: this.modelId || '', article_id: a.id });
			} catch (e) {
				showAlert(Util.cleanError(e && e.message), 'error');
				return;
			}
		}
		this.createBusy = false;
		this.createMsg = null;
		this.createKey = this.createKey + 1;
		showModal('mdlCbdBaru');
	},

	createFormModel() {
		const a = this.article();
		const latest = this.latestPublished();
		const specLabel = a && a.spec_pub_label ? a.spec_pub_label : '';
		let options = [];
		let sources = [];
		if (a && !this.revisions().length) {
			sources = (q_cbd_sources.data || []).map(s => ({
				id: s.id, label: `${s.code} · ${s.season} · ${s.label} terbit${s.dropped ? ' · di-drop' : ''}`,
			}));
			options = [
				{ v: 'NEW', title: 'CBD baru dari specsheet', desc: `Baris dari specsheet ${specLabel}; harga dari master harga. Yield & Loss % diisi.` },
				{
					v: 'COPY', title: 'Copy dari article lain (model sama)', needsSource: true, disabled: !sources.length,
					desc: sources.length
						? 'Baris, warna & supplier tetap dari specsheet article ini; yang di-copy Yield, Loss %, harga quotation/override, dan rekap.'
						: 'Belum ada article lain model ini yang punya CBD terbit.',
				},
			];
		} else if (a && latest) {
			const revs = this.revisions().filter(r => r.stage === a.spec_pub_stage);
			const no = revs.length ? Math.max(...revs.map(r => r.revision_no)) + 1 : 0;
			options = [{
				v: 'NEXT', title: `Revisi berikutnya: ${a.spec_pub_stage} r${no}`,
				desc: `Baris dari specsheet ${specLabel}; Yield, Loss %, harga input & rekap dari ${this.label(latest)}. `
					+ 'Baris yang tidak ada lagi di specsheet ditandai MISSING_IN_SPEC.',
			}];
		}
		return {
			key: this.createKey,
			title: a ? `Buat CBD — ${a.code} · ${a.colorway}` : 'Buat CBD',
			note: specLabel ? `Acuan: specsheet ${this.season() ? this.season().season + ' ' : ''}${specLabel} (terbit terakhir).` : '',
			options,
			sources,
			emptyText: 'Terbitkan atau hapus draft yang ada dulu sebelum membuat revisi baru.',
			busy: this.createBusy,
			message: this.createMsg,
		};
	},

	async saveCreate() {
		const f = cwCbdForm.model || {};
		const a = this.article();
		if (!a) return;
		this.createMsg = null;
		this.createBusy = true;
		try {
			await a_cbd_create.run({ article_id: a.id, mode: f.mode || '', source_article_id: f.source_article_id || '' });
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlCbdBaru');
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return;
			}
			this.createMsg = { type: 'error', text: Util.cleanError(msg) };
			return;
		} finally {
			this.createBusy = false;
		}
		closeModal('mdlCbdBaru');
		const id = a_cbd_create.data && a_cbd_create.data[0] && a_cbd_create.data[0].id;
		showAlert('CBD draft dibuat.', 'success');
		await this.refresh(id);
	},

	// Query a_cbd_delete memakai "Request confirmation before running" = ON
	async deleteDraft() {
		const r = this.revision();
		if (!r || r.status !== 'DRAFT') return;
		if (!await Util.run(a_cbd_delete, { id: r.id }, `Draft CBD ${this.label(r)} dihapus.`)) return;
		await this.refresh('');
	},
}
