// JSObject "BomCtrl" — page Specsheet: grid BOM (Custom Widget cwBomGrid) dan article di revisi.
// cwBomGrid mengirim satu event onAction dengan model.action = { type, ... }; onAction() menjalankan query
// yang sesuai lalu memuat ulang grid. Semua aturan dicek di DB (fn_bom_*, fn_rev_article_set, trg_lock_published).
// Query baca dijalankan dengan params lewat load() / reload().
export default {
	okKey: 0,        // naik setelah tambah baris / subkomponen berhasil -> cwBomGrid mengosongkan form
	busyCount: 0,
	message: null,   // { type, text } ditampilkan di atas grid

	// ---- data ----
	articles() {
		return q_rev_articles.data || [];
	},

	activeArticles() {
		return this.articles().filter(a => a.rev_status === 'ACTIVE');
	},

	// Article season yang belum aktif di revisi (belum masuk atau di-drop) -> msArticleTambah
	addableOptions() {
		return this.articles().filter(a => a.rev_status !== 'ACTIVE').map(a => ({
			label: `${a.code} — ${a.colorway}${a.rev_status === 'DROPPED' ? ' (di-drop)' : ''}`, value: a.id,
		}));
	},

	options() {
		const r = (q_bom_options.data && q_bom_options.data[0]) || {};
		const arr = v => (typeof v === 'string' ? JSON.parse(v || '[]') : (v || []));
		return { components: arr(r.components), materials: arr(r.materials), suppliers: arr(r.suppliers), links: arr(r.links) };
	},

	articleNote() {
		const r = SpecCtrl.revision();
		if (!r) return '';
		const dropped = this.articles().filter(a => a.rev_status === 'DROPPED').map(a => a.code);
		const notIn = this.articles().filter(a => !a.rev_status).map(a => a.code);
		const parts = [`${this.activeArticles().length} article aktif`];
		if (dropped.length) parts.push(`di-drop: ${dropped.join(', ')}`);
		if (notIn.length && SpecCtrl.canEdit()) parts.push(`belum masuk revisi: ${notIn.join(', ')}`);
		return parts.join(' · ');
	},

	// ---- muat ----
	async load() {
		const r = SpecCtrl.revision();
		const s = SpecCtrl.season();
		const jobs = [
			q_rev_articles.run({ revision_id: r ? r.id : '', specsheet_id: SpecCtrl.seasonId || '' }),
			q_bom_grid.run({ revision_id: r ? r.id : '' }),
		];
		if (SpecCtrl.editable()) {
			jobs.push(q_bom_options.run());
			jobs.push(q_season_colors.run({ season: s ? s.season : '' }));
		}
		try {
			await Promise.all(jobs);
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
	},

	async reload(what) {
		const r = SpecCtrl.revision();
		const s = SpecCtrl.season();
		const jobs = [q_bom_grid.run({ revision_id: r ? r.id : '' })];
		if (what.includes('articles')) jobs.push(q_rev_articles.run({ revision_id: r ? r.id : '', specsheet_id: SpecCtrl.seasonId || '' }));
		if (what.includes('options')) jobs.push(q_bom_options.run());
		if (what.includes('colors')) jobs.push(q_season_colors.run({ season: s ? s.season : '' }));
		try { await Promise.all(jobs); } catch (e) { /* abaikan */ }
	},

	// Default model cwBomGrid
	gridModel() {
		const o = this.options();
		return {
			editable: SpecCtrl.editable(),
			articles: this.activeArticles().map(a => ({ id: a.id, code: a.code, colorway: a.colorway })),
			lines: q_bom_grid.data || [],
			components: o.components,
			materials: o.materials,
			suppliers: o.suppliers,
			links: o.links,
			colors: (q_season_colors.data || []).map(c => c.color),
			busy: this.busyCount > 0,
			message: this.message,
			okKey: this.okKey,
			emptyText: SpecCtrl.revision() ? 'Belum ada baris BOM.' : '',
		};
	},

	// ---- aksi dari grid (event onAction) ----
	async onAction() {
		const a = (cwBomGrid.model || {}).action;   // baca dulu — model di-reset saat Default model berubah
		if (!a || !a.type) return;
		const r = SpecCtrl.revision();
		if (!r) return;
		const actions = {
			addLine: [a_bom_add_line, {
				revision_id: r.id, component_id: a.component_id, local_no: a.local_no, local_name: a.local_name,
				material_id: a.material_id, supplier_id: a.supplier_id, process: a.process,
			}, ['options', 'colors']],
			addSub: [a_bom_add_sub, {
				parent_id: a.parent_id, sub_name: a.sub_name, material_id: a.material_id,
				supplier_id: a.supplier_id, process: a.process,
			}, ['options']],
			replaceMaterial: [a_bom_replace_material, { line_id: a.line_id, material_id: a.material_id }, ['options']],
			setSupplier: [a_bom_set_supplier, { line_id: a.line_id, supplier_id: a.supplier_id }, ['options']],
			setProcess: [a_bom_set_process, { line_id: a.line_id, process: a.process }, []],
			setCell: [a_cell_save, { line_id: a.line_id, article_id: a.article_id, color: a.color }, ['colors']],
			dropArticle: [a_rev_article_set, { revision_id: r.id, article_id: a.article_id, status: 'DROPPED' }, ['articles']],
		};
		const def = actions[a.type];
		if (!def) return;
		this.busyCount = this.busyCount + 1;
		try {
			await def[0].run(def[1]);
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };
			await this.reload([]);          // kembalikan grid ke isi DB
			return;
		} finally {
			this.busyCount = Math.max(0, this.busyCount - 1);
		}
		this.message = null;
		if (a.type === 'addLine' || a.type === 'addSub') this.okKey = this.okKey + 1;
		await this.reload(def[2]);
	},

	// Tombol "Masukkan ke Revisi": article terpilih di msArticleTambah jadi ACTIVE (baru masuk / aktif lagi)
	async addArticles() {
		const r = SpecCtrl.revision();
		const ids = msArticleTambah.selectedOptionValues || [];
		if (!r || !ids.length) {
			showAlert('Pilih article dulu.', 'warning');
			return;
		}
		for (const id of ids) {
			if (!await Util.run(a_rev_article_set, { revision_id: r.id, article_id: id, status: 'ACTIVE' })) break;
		}
		resetWidget('msArticleTambah');
		showAlert('Article dimasukkan ke revisi.', 'success');
		await this.reload(['articles']);
	},
}
