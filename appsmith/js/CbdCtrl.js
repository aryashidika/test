// JSObject "CbdCtrl" - page Cost Breakdown (CBD) (?model_id=<model id>&season=<specsheet id>&article=<article id>&from=list|detail|home,
// semua opsional). Dibuka dari Model List / Model Detail / Specsheet / Beranda (Tugas Saya, F10) -> model, season & article
// langsung terpilih; dari sidebar -> pilih dulu di selCbdModel lalu selCbdSeason.
// Chip article + stepper revisi CBD (cwStepper), Buat CBD (cwCbdForm di mdlCbdBaru),
// Hapus Draft, Terbitkan (cwPublishForm di mdlCbdTerbit, F8), Riwayat (tblCbdRiwayat di mdlCbdRiwayat, F8).
// Grid baris, rekap & harga ada di CbdGridCtrl. Izin: lihat = view_cbd (Brand hanya revisi terbit - difilter query)
// · ubah = edit_cbd (Vendor – CBD). Semua dicek lagi di DB.
// CBD per article; acuan = revisi specsheet terbit terakhir season itu (article harus ACTIVE di sana).
// R5: harga per varian × supplier; harga menunggu persetujuan memblokir terbit. R7: copy dari article model asal.
// R12 (T62): semua pemuatan model / season / article / revisi lewat antrean nav() - tidak pernah dua sekaligus, jadi
// isi grid selalu milik article & revisi yang dipilih walau user klik cepat. Gambar riwayat dimuat satu per satu (T60).
export default {
	modelId: '',       // model yang dipilih
	from: '',          // asal halaman (?from=list | detail | home) -> tujuan tombol kembali
	seasonId: '',      // specsheet (season) yang dipilih
	articleId: '',     // article yang dipilih (chip)
	revisionId: '',    // revisi CBD yang dibuka
	firstLoad: true,

	createKey: 0, createBusy: false, createMsg: null,
	pubKey: 0, pubBusy: false, pubMsg: null,

	// Kategori change log CBD (sama dengan Python; DB menerima semuanya)
	CATEGORIES: [
		{ value: 'MATERIAL', label: 'Material / material price' },
		{ value: 'YIELD', label: 'Yield / Loss %' },
		{ value: 'EX_RATE', label: 'Exchange rate' },
		{ value: 'AMORTIZATION', label: 'Amortization' },
		{ value: 'LOP', label: 'LOP' },
		{ value: 'COMPONENT', label: 'Component (from specsheet)' },
		{ value: 'TREATMENT', label: 'Treatment / process' },
		{ value: 'OTHER', label: 'Other' },
	],

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

	// Change log semua revisi CBD article ini (terbaru dulu)
	changeLogs() {
		return q_cbd_change_log.data || [];
	},

	logFor(revisionId) {
		return this.changeLogs().find(l => l.revision_id === revisionId) || null;
	},

	label(r) {
		return Util.revLabel(r);
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
	canPublish() {
		return this.editable();
	},

	// ---- antrean pemuatan (R12, T62) ----
	// Pilihan yang masuk saat masih memuat disimpan di navNext; hanya yang terakhir dijalankan setelah pemuatan
	// berjalan selesai. Muat ulang setelah buat / terbit / hapus (reload) tidak hilang: klik article / revisi menumpang
	// sebagai pilihannya.
	navBusy: false,
	navNext: null,

	async nav(req) {
		const prev = this.navNext;
		let next = req;
		if (prev && prev.type === 'reload' && req.type === 'revision') next = Object.assign({}, prev, { pick: req.id });
		if (prev && prev.type === 'reload' && req.type === 'article') next = Object.assign({}, prev, { article: req.id, pick: '' });
		this.navNext = next;
		if (this.navBusy) return;
		this.navBusy = true;
		try {
			while (this.navNext) {
				const r = this.navNext;
				this.navNext = null;
				try {
					await this.runNav(r);
				} catch (e) {
					showAlert(Util.cleanError(e && e.message), 'error');
				}
			}
		} finally {
			this.navBusy = false;
		}
	},

	async runNav(r) {
		if (r.type === 'init') return this.loadInit();
		if (r.type === 'model') {
			this.modelId = r.id || '';
			return this.loadModel('');
		}
		if (r.type === 'season') {
			this.seasonId = r.id || '';
			this.articleId = '';
			this.revisionId = '';
			return this.loadSeason();
		}
		if (r.type === 'article') {
			if (!r.id || r.id === this.articleId) return;
			this.articleId = r.id;
			this.revisionId = '';
			return this.loadArticle();
		}
		if (r.type === 'revision') {
			if (!r.id || r.id === this.revisionId) return;
			this.revisionId = r.id;
			return CbdGridCtrl.load();
		}
		if (r.type === 'reload') {
			// status chip & revisi dimuat ulang (setelah buat / terbit / hapus / refresh dari specsheet)
			try { await q_cbd_articles.run({ specsheet_id: this.seasonId || '' }); } catch (e) { /* abaikan */ }
			if (r.article && r.article !== this.articleId) this.articleId = r.article;
			this.revisionId = r.pick || '';
			return this.loadArticle(r.pick);
		}
	},

	// ---- muat data ----
	// Dipanggil Auth.pageQueries(). Model & season dari URL kalau ada.
	async init() {
		return this.nav({ type: 'init' });
	},

	async loadInit() {
		try {
			await q_cbd_models.run();
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
		const url = appsmith.URL.queryParams;
		if (this.firstLoad) this.from = url.from || '';
		const want = this.modelId || (this.firstLoad ? url.model_id : '');
		this.modelId = this.models().some(m => m.id === want) ? want : '';
		if (want && !this.modelId) showAlert('Model not found. Select a model above.', 'warning');
		await this.loadModel(this.firstLoad ? url.season : this.seasonId, this.firstLoad ? url.article : '');
		this.firstLoad = false;
	},

	// Muat model + season-nya, pilih season (wantSeason atau season terbaru), lalu article (wantArticle atau
	// article aktif pertama).
	async loadModel(wantSeason, wantArticle) {
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
		await this.loadSeason(wantArticle);
	},

	pickModel(id) {
		return this.nav({ type: 'model', id: id || '' });
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

	pickSeason(id) {
		return this.nav({ type: 'season', id: id || '' });
	},

	// Muat revisi CBD article ini lalu buka: pickId, revisi yang sedang dibuka, draft, atau terbit terakhir.
	async loadArticle(pickId) {
		try {
			await Promise.all([
				q_cbd_revisions.run({ article_id: this.articleId || '' }),
				q_cbd_change_log.run({ article_id: this.articleId || '' }),
			]);
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
	selectArticle() {
		const id = (cwStepper.model || {}).selectedArticleId;
		if (!id) return;
		return this.nav({ type: 'article', id });
	},

	// cwStepper onSelect
	selectRevision() {
		const id = (cwStepper.model || {}).selectedId;
		if (!id) return;
		return this.nav({ type: 'revision', id });
	},

	// Setelah buat / terbit / hapus: status chip & revisi dimuat ulang
	refresh(pickRevisionId) {
		return this.nav({ type: 'reload', pick: pickRevisionId || '' });
	},

	// ---- tampilan ----
	esc(v) {
		return String(v ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
	},

	modelOptions() {
		const all = !(Auth.me && Auth.me.factory_id);     // Brand / System Admin: semua pabrik
		return this.models().map(m => ({ label: all ? `${m.name} · ${m.factory_name}` : m.name, value: m.id }));
	},

	seasonOptions() {
		return this.seasons().map(s => ({
			label: `${s.season} (${s.spec_pub_label ? 'specsheet ' + s.spec_pub_label : 'specsheet not published'})`, value: s.id,
		}));
	},

	headerText() {
		const m = this.model();
		if (!m) return this.modelId && q_cbd_model.isLoading ? 'Loading…' : 'Select a model and season first.';
		const e = v => this.esc(v || '-');
		return `<b style="font-size:18px">${e(m.name)}</b> <span style="color:#6b7280">· ${e(m.factory_name)}</span><br>`
			+ `<span style="color:#6b7280">Category: ${e(m.category)} · Factory: ${e(m.factory)} · Size Range: ${e(m.size_range)}`
			+ ` · Sample Size: ${e(m.sample_size)}</span>`;
	},

	// Chip article: status CBD (Brand hanya melihat terbit - draft_* kosong dari query)
	chip(a) {
		if (a.spec_status === 'DROPPED') return { badge: a.pub_label ? `DROPPED · ${a.pub_label}` : 'DROPPED', tone: 'muted' };
		if (a.draft_id) return { badge: `DRAFT ${a.draft_label}${a.draft_stale ? ' · new specsheet' : ''}`, tone: 'draft' };
		// R13: CBD terbit terakhir tertinggal stage specsheet (mis. CBD SMS terbit, specsheet sudah GTM)
		if (a.pub_id && a.pub_behind) return { badge: `NEEDS CBD ${Util.stageLabel(a.spec_pub_stage)} · ${a.pub_label}`, tone: 'danger' };
		if (a.pub_id && a.pub_sync === 'NEEDS_REVISION') return { badge: `NEEDS REVISION · ${a.pub_label}`, tone: 'danger' };
		if (a.pub_id) return { badge: `PUBLISHED ${a.pub_label}`, tone: 'ok' };
		if (a.spec_status === 'NOT_PUBLISHED') return { badge: 'SPECSHEET NOT PUBLISHED', tone: 'muted' };
		return { badge: 'NO CBD YET', tone: 'info' };
	},

	// R19: article tanpa nomor dikenali dari colorway (chip, judul, nama file Excel)
	artLabel(a) {
		return a ? (a.no_code ? `${a.code} ${a.colorway}` : a.code) : '';
	},

	stepperModel() {
		return {
			articles: this.articles().map(a => Object.assign({ id: a.id, code: this.artLabel(a), colorway: a.colorway }, this.chip(a))),
			selectedArticleId: this.articleId,
			articleEmptyText: !this.modelId ? 'Select a model first.'
				: !this.seasonId ? 'This model has no seasons yet.' : 'No articles in this season yet.',
			revisions: this.revisions().map(r => ({
				id: r.id, stage: r.stage, revision_no: r.revision_no, status: r.status,
				needsRevision: r.status === 'PUBLISHED' && r.sync_status === 'NEEDS_REVISION',
			})),
			selectedId: this.revisionId,
			emptyText: !this.articleId ? '' : (this.canCreate() ? 'No CBD yet. Click "+ Create CBD".' : 'No published CBD yet.'),
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
			t += `<span style="color:#6b7280">Article ${e(a.code)} is dropped in the latest published specsheet. The CBD is view only.</span><br>`;
		} else if (a.spec_status === 'NOT_PUBLISHED') {
			t += `<span style="color:#6b7280">Article ${e(a.code)} is not in a published specsheet revision. Publish the specsheet first.</span><br>`;
		}
		if (!r) return t;
		t += `<b>${e(a.code)} · ${e(a.colorway)} · ${e(this.label(r))}</b> · `
			+ `<b style="color:${Util.statusColor(r.status)}">${r.status}</b>`;
		if (r.status === 'PUBLISHED') {
			t += ` · <b style="color:${Util.statusColor(r.sync_status)}">${r.sync_status}</b>`;
			t += ` · published ${Util.fmtDateTime(r.published_at)} by ${e(r.published_by || '-')}`;
		} else {
			t += ` · created ${Util.fmtDateTime(r.created_at)} by ${e(r.created_by || '-')}`;
		}
		t += ` · reference specsheet ${e(r.spec_label)}`;
		if (r.source_label) t += ` · source: ${e(r.source_season)} / ${e(r.source_article)} / ${e(r.source_label)}`;
		if (r.id === a.pub_id && a.pub_behind) {
			t += `<br><span style="color:#dc2626">Specsheet published ${e(a.spec_pub_label)}. Create the ${e(Util.stageLabel(a.spec_pub_stage))} CBD with "+ Create CBD".</span>`;
		} else if (r.status === 'PUBLISHED' && r.sync_status === 'NEEDS_REVISION') {
			t += `<br><span style="color:#dc2626">Specsheet ${e(a.spec_pub_label)} changed lines / suppliers / colors of this article. Create the next CBD revision.</span>`;
		}
		const log = r.status === 'PUBLISHED' ? this.logFor(r.id) : null;
		if (log) t += `<br><span style="color:#6b7280">Change (${e(log.category)}): ${e(log.reason)}</span>`;
		return t;
	},

	// ---- navigasi ----
	backToList() {
		return this.from === 'list' || !this.model();
	},

	backLabel() {
		if (this.from === 'home') return '← Home';
		return this.backToList() ? '← Model List' : '← Model Detail';
	},

	openModel() {
		if (this.from === 'home') return navigateTo('Home');
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
		try {
			await q_cbd_stages.run({ article_id: a.id });      // R13: pilihan stage
			if (!this.revisions().length) await q_cbd_sources.run({ model_id: this.modelId || '', article_id: a.id });
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
			return;
		}
		this.createBusy = false;
		this.createMsg = null;
		this.createKey = this.createKey + 1;
		showModal('mdlCbdBaru');
	},

	// R13: stage dipilih di form (cwCbdForm mengganti {spec} / {next} di judul & keterangan sesuai stage terpilih)
	createFormModel() {
		const a = this.article();
		const latest = this.latestPublished();
		const specLabel = '{spec}';
		const stages = (a ? (q_cbd_stages.data || []) : []).map(s => ({
			v: s.stage, label: Util.stageLabel(s.stage), spec: s.spec_label, next: s.next_label, disabled: !s.available, note: s.note || '',
			isDefault: !!s.is_default,
		}));
		let options = [];
		let sources = [];
		if (a && !stages.some(s => !s.disabled)) {
			options = [];
		} else if (a && !this.revisions().length) {
			sources = (q_cbd_sources.data || []).map(s => ({
				id: s.id,
				label: `${s.is_cross ? s.model_name + ' (origin model) · ' : ''}${s.code} · ${s.season} · ${s.label} published${s.dropped ? ' · dropped' : ''}`,
			}));
			options = [
				{ v: 'NEW', title: 'New CBD from specsheet', desc: `Lines from specsheet ${specLabel}; prices from master prices. Fill in Yield & Loss %.` },
				{
					v: 'COPY', title: 'Copy from another article (same model / origin model)', needsSource: true, disabled: !sources.length,
					desc: sources.length
						? 'Lines, colors & suppliers come from this article\'s specsheet; Yield, Loss %, quotation prices, and recap are copied. '
							+ 'From the origin model (cross-model copy): Yield/Loss only for origin lines with the same material + dimension; only rate & LOP are copied.'
						: 'No other article of this model (or its origin model) has a published CBD.',
				},
			];
		} else if (a && latest) {
			options = [{
				v: 'NEXT', title: 'Next revision: {next}',
				desc: `Lines from specsheet ${specLabel}; Yield, Loss %, entered prices & recap from ${this.label(latest)}. `
					+ 'Lines no longer in the specsheet are marked MISSING_IN_SPEC.',
			}];
		}
		return {
			key: this.createKey,
			title: a ? `Create CBD: ${a.code} · ${a.colorway}` : 'Create CBD',
			note: `Reference: specsheet ${this.season() ? this.season().season + ' ' : ''}{spec} (latest published in that stage).`,
			stages,
			options,
			sources,
			emptyText: this.draft() ? 'Publish or delete the current draft before creating a new revision.'
				: 'No stage is available for a CBD (article is not active in a published specsheet).',
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
			await a_cbd_create.run({ article_id: a.id, mode: f.mode || '', source_article_id: f.source_article_id || '',
				stage: f.stage || '' });
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlCbdBaru');
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
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
		showAlert('CBD draft created.', 'success');
		await this.refresh(id);
	},

	// ---- terbitkan (F8) ----
	// Checklist + rincian perubahan (R11, A4) dimuat ulang setiap modal dibuka (isi grid & harga master bisa berubah).
	async openPublish() {
		const r = this.revision();
		if (!r || r.status !== 'DRAFT') return;
		try {
			await Promise.all([q_cbd_checklist.run({ revision_id: r.id }), q_cbd_bridge.run({ revision_id: r.id })]);
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			showAlert(Util.cleanError(msg), 'error');
			return;
		}
		this.pubBusy = false;
		this.pubMsg = null;
		this.pubKey = this.pubKey + 1;
		showModal('mdlCbdTerbit');
	},

	publishFormModel() {
		const r = this.revision();
		const a = this.article();
		const c = (q_cbd_checklist.data && q_cbd_checklist.data[0]) || null;
		const checks = !c ? [] : [
			{ label: `Reference specsheet = latest published in stage ${Util.stageLabel(c.stage)}`, ok: !c.spec_stale, blocking: true,
				detail: c.spec_stale ? 'Click "Refresh from Specsheet" above the grid' : '' },
			{ label: 'Exchange rate filled in', ok: !!c.rate_ok, blocking: true,
				detail: c.rate_ok ? '' : 'Fill in the Exchange rate in the recap' },
			{ label: 'No prices waiting for approval', ok: !c.pending_prices, blocking: true,
				detail: c.pending_prices ? `${c.pending_prices} lines waiting for Manager Costing: ${c.pending_list || ''}` : '' },
			{ label: 'Master prices match the current master', ok: c.stale_prices === 0, blocking: true,
				detail: c.stale_prices ? `${c.stale_prices} lines changed. Click "Refresh Prices from Master"` : '' },
			{ label: 'Priced lines have a Yield', ok: c.no_yield_count === 0, blocking: true,
				detail: c.no_yield_count ? `${c.no_yield_count} lines without Yield (yellow box)` : '' },
			// R11 (T56, keputusan user 13 Okt 2026): peringatan saja - baris ber-Yield yang belum berharga didaftar
			// (kemungkinan lupa); baris tanpa harga & tanpa Yield tidak didaftar (memang tanpa biaya).
			// R17 (keputusan user 22 Okt 2026): mulai SMS memblokir (price_required), Pullover / Preview tetap peringatan
			{ label: 'Lines with Yield have a price', ok: c.unpriced_count === 0, blocking: !!c.price_required,
				detail: !c.unpriced_count ? ''
					: c.price_required ? `${c.unpriced_count} lines without price: ${c.unpriced_list || ''}. From SMS every line with a Yield needs a price (or No charge)`
					: `${c.unpriced_count} lines will publish with cost 0: ${c.unpriced_list || ''}. Fill in the price if it was missed` },
		];
		if (c && c.estimate_count) {
			checks.push({ label: `${c.estimate_count} lines use an estimate price (no Material Code yet)`, ok: !c.price_required,
				blocking: !!c.price_required,
				detail: c.price_required ? 'Estimates are not allowed from SMS' : 'Allowed in Pullover and Preview. From SMS the master price is required.' });
		}
		if (c && c.no_charge_count) {
			checks.push({ label: `${c.no_charge_count} lines with no charge (cost 0)`, ok: true, blocking: false,
				detail: 'The reason shows in the grid & Excel export.' });
		}
		if (c && c.spec_status !== 'ACTIVE') {
			checks.unshift({ label: 'Article active in the published specsheet', ok: false, blocking: true,
				detail: 'Article dropped / not published. This CBD cannot be published' });
		}
		const requiresReason = c ? !!c.requires_reason : true;
		const rows = this.bridgeRows();
		const b = rows[0] || null;
		return {
			key: this.pubKey,
			title: `Publish CBD ${a ? a.code + ' · ' : ''}${this.label(r)}`,
			checks,
			blocked: !c || !!c.blocked,
			blockedWhere: 'in the CBD grid / recap',
			requiresReason,
			categories: this.CATEGORIES,
			defaultCategory: requiresReason ? '' : 'OTHER',
			// R11 (A4): rincian perubahan vs revisi terbit sebelumnya - nilai dari DB, kategori & uraian boleh diubah
			bridge: rows.map(x => ({ key: x.key, category: x.category, description: x.description, amount: Number(x.amount) })),
			bridgeInfo: b ? { prevLabel: b.prev_label, prevFob: b.prev_fob, fob: b.fob } : null,
			maxImages: 5,
			busy: this.pubBusy,
			message: this.pubMsg,
		};
	},

	// Gambar dari cwPublishForm dilampirkan ke change log setelah terbit (fn_change_log_attach, F10b).
	async publish() {
		const f = cwPublishForm.model || {};
		const images = Array.isArray(f.images) ? f.images : [];
		const r = this.revision();
		if (!r) return;
		this.pubMsg = null;
		this.pubBusy = true;
		try {
			await a_cbd_publish.run({
				revision_id: r.id, category: f.category || '', reason: f.reason || '',
				bridge: JSON.stringify(Array.isArray(f.bridge) ? f.bridge : []),
			});
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlCbdTerbit');
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			this.pubMsg = { type: 'error', text: Util.cleanError(msg) };
			return;
		} finally {
			this.pubBusy = false;
		}
		const logId = ((a_cbd_publish.data || [])[0] || {}).id;
		const failed = await this.attachImages(logId, images);
		closeModal('mdlCbdTerbit');
		showAlert(`CBD ${this.label(r)} published.`
			+ (failed ? ` ${failed} image(s) could not be attached.` : (images.length ? ` ${images.length} image(s) attached.` : '')),
			failed ? 'warning' : 'success');
		await this.refresh(r.id);
	},

	// Mengembalikan jumlah gambar yang gagal dilampirkan
	async attachImages(logId, images) {
		if (!images.length) return 0;
		let failed = 0;
		this.pubBusy = true;
		for (const img of images) {
			try {
				await a_change_log_attach.run({ log_id: logId, file_name: img.name || 'image', data: img.data || '' });
			} catch (e) {
				failed += 1;
			}
		}
		this.pubBusy = false;
		return failed;
	},

	// R11 (A4): rincian perubahan revisi yang terakhir dimuat q_cbd_bridge (form terbit & export)
	bridgeRows() {
		return q_cbd_bridge.data || [];
	},

	// ---- riwayat (F8) ----
	historyLabel() {
		const n = this.changeLogs().length;
		return n ? `History (${n})` : 'History';
	},

	openHistory() {
		this.galleryLogId = '';
		this.galleryImages = [];
		showModal('mdlCbdRiwayat');
	},

	// ---- gambar change log (F10b): baris riwayat dipilih -> gambar tampil di cwImageGallery ----
	// R12 (T60): q_change_log_images = daftar saja; isi gambar lewat q_change_log_image satu per satu (satu respons =
	// satu gambar, tidak melewati batas ukuran respons Appsmith). Gambar tampil bertahap.
	galleryLogId: '',
	galleryImages: [],
	galleryLoading: false,

	async showImages(row) {
		const id = row && row.id ? row.id : '';
		this.galleryLogId = id;
		this.galleryImages = [];
		if (!id || !row.image_count) return;
		this.galleryLoading = true;
		let failed = 0;
		try {
			const list = await q_change_log_images.run({ log_id: id });
			for (const i of list || []) {
				if (this.galleryLogId !== id) return;        // baris lain dipilih
				try {
					const rows = await q_change_log_image.run({ id: i.id });
					const d = rows && rows[0];
					if (d && this.galleryLogId === id) {
						this.galleryImages = this.galleryImages.concat([
							{ id: i.id, name: i.file_name, mime: i.mime_type, size: i.size_bytes, data: d.data }]);
					}
				} catch (e) {
					failed += 1;
				}
			}
			if (failed) showAlert(`${failed} image(s) could not be loaded.`, 'warning');
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		} finally {
			if (this.galleryLogId === id) this.galleryLoading = false;
		}
	},

	galleryModel() {
		const log = this.changeLogs().find(l => l.id === this.galleryLogId) || null;
		const images = log && log.image_count ? this.galleryImages : [];
		return {
			title: log ? `Images: ${log.revision_label}` : 'Images',
			emptyText: !log ? 'Select a history row to see its images.'
				: log.image_count ? 'Images could not be loaded.' : 'No images in this publish.',
			loading: !!log && !!log.image_count && this.galleryLoading && !images.length,
			images,
		};
	},

	// cwImageGallery onDownload
	downloadImage() {
		const m = cwImageGallery.model || {};
		const img = (this.galleryModel().images || []).find(i => i.id === m.downloadId);
		if (img) download(`data:${img.mime};base64,${img.data}`, img.name, img.mime);
	},

	// Query a_cbd_delete memakai "Request confirmation before running" = ON
	async deleteDraft() {
		const r = this.revision();
		if (!r || r.status !== 'DRAFT') return;
		if (!await Util.run(a_cbd_delete, { id: r.id }, `CBD draft ${this.label(r)} deleted.`)) return;
		await this.refresh('');
	},
}
