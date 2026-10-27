// JSObject "SpecCtrl" - page Specsheet (?model_id=<model id>&season=<specsheet id>&from=list|detail|home, semua opsional).
// Dibuka dari Model List / Model Detail / Beranda (Tugas Saya, F10) -> model & season langsung terpilih; dari sidebar -> pilih dulu
// di selSpecModel lalu selSpecSeason. Stepper revisi (cwStepper), Buat Revisi (cwRevisionForm di mdlRevisi), Hapus Draft.
// Terbitkan (cwPublishForm di mdlTerbit, F6) & Riwayat (tblRiwayat di mdlRiwayat, F6).
// Grid BOM & article revisi ada di BomCtrl. Izin: lihat = view_specsheet (Brand hanya revisi terbit - difilter
// query) · ubah = edit_specsheet (Vendor – Specsheet). Semua dicek lagi di DB.
// Query q_spec_model, q_spec_seasons, q_revisions, q_change_log dijalankan dengan params (loadModel / loadSeason),
// q_publish_checklist saat modal Terbitkan dibuka;
// isi revisi lewat BomCtrl.load().
// R4: checklist terbit + sel kuning & supplier INACTIVE. R7: Buat Revisi bisa copy dari model lain (pabrik & kategori
// sama, q_copy_model_sources); header menampilkan "disalin dari".
// R12 (T62): semua pemuatan model / season / revisi lewat antrean nav() - tidak pernah dua sekaligus, jadi isi grid
// selalu milik revisi yang dipilih walau user klik cepat. Gambar riwayat dimuat satu per satu (T60).
export default {
	modelId: '',       // model yang dipilih
	from: '',          // asal halaman (?from=list | detail | home) -> tujuan tombol kembali
	seasonId: '',      // specsheet (season) yang dipilih
	revisionId: '',    // revisi yang dibuka
	firstLoad: true,

	revKey: 0, revBusy: false, revMsg: null,
	pubKey: 0, pubBusy: false, pubMsg: null,

	STAGES: ['PULL', 'PREV', 'SMS', 'GTM', 'PROD'],   // R14: + Preview; label lewat Util.stageLabel

	// Kategori change log untuk specsheet (DB juga menerima EX_RATE / LOP / AMORTIZATION / YIELD untuk CBD)
	CATEGORIES: [
		{ value: 'MATERIAL', label: 'Material (replace / add material, color)' },
		{ value: 'COMPONENT', label: 'Component (add / delete lines)' },
		{ value: 'TREATMENT', label: 'Treatment / process' },
		{ value: 'OTHER', label: 'Other' },
	],

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

	changeLogs() {
		return q_change_log.data || [];
	},

	logFor(revisionId) {
		return this.changeLogs().find(l => l.revision_id === revisionId) || null;
	},

	label(r) {
		return Util.revLabel(r);
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

	// ---- antrean pemuatan (R12, T62) ----
	// Pilihan yang masuk saat masih memuat disimpan di navNext; hanya yang terakhir dijalankan setelah pemuatan
	// berjalan selesai. Muat ulang setelah buat / terbit / hapus (reload) tidak hilang: klik revisi menumpang sebagai
	// revisi yang dipilih.
	navBusy: false,
	navNext: null,

	async nav(req) {
		const prev = this.navNext;
		this.navNext = prev && prev.type === 'reload' && req.type === 'revision'
			? Object.assign({}, prev, { pick: req.id }) : req;
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
			this.revisionId = '';
			return this.loadSeason();
		}
		if (r.type === 'revision') {
			if (!r.id || r.id === this.revisionId) return;
			this.revisionId = r.id;
			return BomCtrl.load();
		}
		if (r.type === 'reload') {
			if (r.seasons) await this.refreshSeasons();
			if (r.clear) this.revisionId = '';
			return this.loadSeason(r.pick);
		}
	},

	// ---- muat data ----
	// Dipanggil Auth.pageQueries(). Model & season dari URL (dari Model List / Model Detail) kalau ada.
	async init() {
		return this.nav({ type: 'init' });
	},

	async loadInit() {
		try {
			await q_spec_models.run();
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
		const url = appsmith.URL.queryParams;
		if (this.firstLoad) this.from = url.from || '';
		const want = this.modelId || (this.firstLoad ? url.model_id : '');
		this.modelId = this.models().some(m => m.id === want) ? want : '';
		if (want && !this.modelId) showAlert('Model not found. Select a model above.', 'warning');
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

	pickModel(id) {
		return this.nav({ type: 'model', id: id || '' });
	},

	// Muat revisi season ini lalu buka revisi: pickId, revisi yang sedang dibuka, draft, atau terbit terakhir.
	async loadSeason(pickId) {
		try {
			await Promise.all([
				q_revisions.run({ specsheet_id: this.seasonId || '' }),
				q_change_log.run({ specsheet_id: this.seasonId || '' }),
			]);
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
		const revs = this.revisions();
		const keep = revs.find(r => r.id === (pickId || this.revisionId));
		const pick = keep || this.draft() || this.latestPublished() || revs[revs.length - 1] || null;
		this.revisionId = pick ? pick.id : '';
		await BomCtrl.load();
	},

	pickSeason(id) {
		return this.nav({ type: 'season', id: id || '' });
	},

	// cwStepper onSelect
	selectRevision() {
		const id = (cwStepper.model || {}).selectedId;
		if (!id) return;
		return this.nav({ type: 'revision', id });
	},

	async refreshSeasons() {
		try { await q_spec_seasons.run({ model_id: this.modelId || '' }); } catch (e) { /* abaikan */ }
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
		return this.seasons().map(s => ({ label: `${s.season} (${s.revision_count} revisions)`, value: s.id }));
	},

	headerText() {
		const m = this.model();
		if (!m) return this.modelId && q_spec_model.isLoading ? 'Loading…' : 'Select a model and season first.';
		const e = v => this.esc(v || '-');
		return `<b style="font-size:18px">${e(m.name)}</b> <span style="color:#6b7280">· ${e(m.factory_name)}</span><br>`
			+ `<span style="color:#6b7280">Category: ${e(m.category)} · Gender: ${e(m.gender)} · Outsole Mould: ${e(m.outsole_mold)}`
			+ ` · Last No.: ${e(m.last_no)} · Construction: ${e(m.construction)} · Size Range: ${e(m.size_range)}`
			+ ` · Sample Size: ${e(m.sample_size)}</span>`;
	},

	stepperModel() {
		return {
			revisions: this.revisions().map(r => ({ id: r.id, stage: r.stage, revision_no: r.revision_no, status: r.status })),
			selectedId: this.revisionId,
			emptyText: !this.modelId ? 'Select a model first.'
				: !this.seasonId ? 'This model has no seasons yet.'
				: (this.canEdit() ? 'No revisions yet. Click "+ Create".' : 'No published revisions yet.'),
		};
	},

	revisionText() {
		const r = this.revision();
		const s = this.season();
		if (!this.modelId) return '';
		if (!this.seasonId) {
			return 'This model has no seasons yet. Add seasons & articles on the Model Detail page.';
		}
		if (!r) return '';
		const e = v => this.esc(v);
		let t = `<b>${e(s ? s.season : '')} · ${e(this.label(r))}</b> · `
			+ `<b style="color:${Util.statusColor(r.status)}">${r.status}</b>`;
		if (r.status === 'PUBLISHED') t += ` · published ${Util.fmtDateTime(r.published_at)} by ${e(r.published_by || '-')}`;
		else t += ` · created ${Util.fmtDateTime(r.created_at)} by ${e(r.created_by || '-')}`;
		if (r.source_label) {
			t += r.source_model ? ` · copied from ${e(r.source_model)} · ${e(r.source_season)} · ${e(r.source_label)}`
				: ` · source: ${e(r.source_season)} ${e(r.source_label)}`;
		}
		const log = r.status === 'PUBLISHED' ? this.logFor(r.id) : null;
		if (log) t += `<br><span style="color:#6b7280">Change (${e(log.category)}): ${e(log.reason)}</span>`;
		if (this.canEdit() && r.status === 'PUBLISHED' && this.draft()) {
			t += ` · <span style="color:#d97706">draft ${e(this.label(this.draft()))}</span>`;
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
		if (this.from === 'home') return '← Home';
		return this.backToList() ? '← Model List' : '← Model Detail';
	},

	openModel() {
		if (this.from === 'home') return navigateTo('Home');
		const m = this.model();
		if (this.backToList()) return navigateTo('Model List');
		navigateTo('Model Detail', this.seasonId ? { id: m.id, season: this.seasonId } : { id: m.id });
	},

	openCbd() {
		const m = this.model();
		if (!m) return;
		const p = { model_id: m.id };
		if (this.seasonId) p.season = this.seasonId;
		if (this.from) p.from = this.from;   // tombol kembali di CBD mengarah ke page asal yang sama
		navigateTo('Cost Breakdown (CBD)', p);
	},

	// ---- buat revisi ----
	async openCreate() {
		// R7: sumber copy lintas model (pabrik & kategori sama) dimuat setiap modal dibuka
		if (!this.revisions().length) {
			try { await q_copy_model_sources.run({ model_id: this.modelId || '' }); } catch (e) { /* daftar kosong */ }
		}
		this.revBusy = false;
		this.revMsg = null;
		this.revKey = this.revKey + 1;
		showModal('mdlRevisi');
	},

	revisionFormModel() {
		const latest = this.latestPublished();
		const revs = this.revisions();
		let nextRevision = '';
		let nextStages = [];
		if (latest) {
			const maxNo = Math.max(...revs.filter(r => r.stage === latest.stage).map(r => r.revision_no));
			nextRevision = Util.revLabel({ stage: latest.stage, revision_no: maxNo + 1 });
			// R14: stage berikutnya boleh melompat; pilihan = semua stage di atas stage terbit terakhir (default yang pertama)
			nextStages = this.STAGES.slice(this.STAGES.indexOf(latest.stage) + 1)
				.map(v => ({ v, label: Util.revLabel({ stage: v, revision_no: 0 }) }));
		}
		const s = this.season();
		return {
			key: this.revKey,
			season: s ? s.season : '',
			hasRevisions: revs.length > 0,
			latestLabel: latest ? this.label(latest) : null,
			nextRevisionLabel: nextRevision,
			nextStageLabel: nextStages.length ? nextStages[0].label : null,
			nextStages,
			stages: this.STAGES.map(v => ({ v, label: Util.stageLabel(v) })),
			copySources: this.seasons().filter(x => x.id !== this.seasonId && x.latest_pub_id)
				.map(x => ({ id: x.id, season: x.season, label: x.latest_pub_label })),
			modelSources: (q_copy_model_sources.data || []).map(x => ({
				id: x.id,
				label: `${x.model_name} · ${x.season} · ${x.label} published${x.outsole_mold ? ' · Mold ' + x.outsole_mold : ''}`,
				summary: `Will copy ${x.line_count} BOM lines from ${x.model_name} · ${x.season} · ${x.label}.`,
			})),
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
				specsheet_id: this.seasonId, mode: f.mode === 'COPY_MODEL' ? 'COPY' : f.mode, stage: f.stage || '',
				source_id: f.source_specsheet_id || '',
			});
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlRevisi');
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
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
		showAlert('Draft revision created.', 'success');
		await this.nav({ type: 'reload', seasons: true, pick: id });
	},

	// ---- terbitkan (F6) ----
	// Checklist dimuat ulang setiap modal dibuka (isi grid bisa berubah).
	async openPublish() {
		const r = this.revision();
		if (!r || r.status !== 'DRAFT') return;
		try {
			await q_publish_checklist.run({ revision_id: r.id });
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
		showModal('mdlTerbit');
	},

	publishFormModel() {
		const r = this.revision();
		const s = this.season();
		const c = (q_publish_checklist.data && q_publish_checklist.data[0]) || null;
		const checks = !c ? [] : [
			{ label: 'At least one active article', ok: c.active_articles > 0, blocking: true,
				detail: `${c.active_articles} active article(s)` },
			{ label: 'Every active article is used in the BOM', ok: !c.unused_articles, blocking: true,
				detail: c.unused_articles ? `Not used (no color in any line): ${c.unused_articles}` : '' },
			{ label: 'No INACTIVE materials', ok: !c.inactive_materials, blocking: true,
				detail: c.inactive_materials || '' },
			{ label: 'All lines have a supplier', ok: c.no_supplier_lines === 0, blocking: true,
				detail: c.no_supplier_lines ? `${c.no_supplier_lines} lines without supplier. Fill in the supplier in the BOM grid` : '' },
			// R17 (keputusan user 22 Okt 2026): wajib mulai SMS (code_required); Pullover / Preview = peringatan
			{ label: 'All colors have a Material Code (no yellow cells)', ok: !c.yellow_cells, blocking: !!c.code_required,
				detail: !c.yellow_cells ? ''
					: c.code_required ? `${c.yellow_cells} yellow cells: ${c.yellow_list || ''}. Required from SMS. Click Register in that cell`
					: `${c.yellow_cells} yellow cells: ${c.yellow_list || ''}. Allowed in Pullover and Preview; required from SMS` },
			// R19 (keputusan user 26 Okt 2026): nomor artikel wajib di Production (article_required); SMS / GTM = peringatan
			{ label: 'All articles have an article no.', ok: !c.no_code_articles, blocking: !!c.article_required,
				detail: !c.no_code_articles ? ''
					: c.article_required ? `${c.no_code_articles} article(s) without article no. (colorway: ${c.no_code_list || ''}). Required in Production. Fill it in Model Detail`
					: `${c.no_code_articles} article(s) without article no. (colorway: ${c.no_code_list || ''}). Allowed before Production; required in Production` },
			{ label: 'No inactive suppliers', ok: !c.inactive_suppliers, blocking: true,
				detail: c.inactive_suppliers ? `${c.inactive_suppliers}. Change the supplier in the BOM grid` : '' },
		];
		const requiresReason = c ? !!c.requires_reason : true;
		return {
			key: this.pubKey,
			title: `Publish ${s ? s.season + ' · ' : ''}${this.label(r)}`,
			checks,
			blocked: !c || !!c.blocked,
			requiresReason,
			categories: this.CATEGORIES,
			defaultCategory: requiresReason ? '' : 'OTHER',
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
			await a_revision_publish.run({ revision_id: r.id, category: f.category || '', reason: f.reason || '' });
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlTerbit');
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
		const logId = ((a_revision_publish.data || [])[0] || {}).id;
		const failed = await this.attachImages(logId, images);
		closeModal('mdlTerbit');
		showAlert(`Revision ${this.label(r)} published.`
			+ (failed ? ` ${failed} image(s) could not be attached.` : (images.length ? ` ${images.length} image(s) attached.` : '')),
			failed ? 'warning' : 'success');
		await this.nav({ type: 'reload', seasons: true, pick: r.id });
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

	// ---- riwayat (F6) ----
	historyLabel() {
		const n = this.changeLogs().length;
		return n ? `History (${n})` : 'History';
	},

	openHistory() {
		this.galleryLogId = '';
		this.galleryImages = [];
		showModal('mdlRiwayat');
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

	// Query a_revision_delete memakai "Request confirmation before running" = ON
	async deleteDraft() {
		const r = this.revision();
		if (!r || r.status !== 'DRAFT') return;
		if (!await Util.run(a_revision_delete, { id: r.id }, `Draft ${this.label(r)} deleted.`)) return;
		await this.nav({ type: 'reload', seasons: true, clear: true });
	},
}
