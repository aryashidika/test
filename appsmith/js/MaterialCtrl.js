export default {
	// R2: daftar material INDUK milik pabrik user (Brand: semua pabrik). Kode, thickness & warna ada di varian
	// (Material Detail). Tanpa usulan/approval; harga kembali di R3.
	form: { name: '', category: '', uom: '', price_method: 'CATALOG', status: 'ACTIVE' },
	formKey: 0,        // naik setiap modal dibuka -> cwMaterialForm mengisi ulang field
	busy: false,
	message: null,     // { type, text } ditampilkan di dalam cwMaterialForm
	similar: [],       // nama mirip (fn_similar_names) untuk teks similarFor
	similarFor: '',
	similarSeq: 0,

	statusOptions: [
		{ label: 'ACTIVE', value: 'ACTIVE' },
		{ label: 'INACTIVE', value: 'INACTIVE' },
	],

	// R11 (S9): q_materials dibatasi 500 baris — beri tahu bila hasil sebenarnya lebih banyak
	limitNote() {
		const rows = q_materials.data || [];
		const total = rows.length ? Number(rows[0].total_count) || rows.length : 0;
		return total > rows.length
			? `Menampilkan ${Util.fmtNum(rows.length)} dari ${Util.fmtNum(total)} material — persempit dengan pencarian / filter.` : '';
	},

	canManage() {
		return Auth.can('manage_master');
	},

	canAdd() {
		return this.canManage();
	},

	canViewPrice() {
		return Auth.can('view_price');
	},

	// q_material_meta: categories & uoms (teks dipisah "|") dari material pabrik user
	meta() {
		const r = (q_material_meta.data && q_material_meta.data[0]) || {};
		const split = s => String(s || '').split('|').filter(x => x);
		return { categories: split(r.categories), uoms: split(r.uoms) };
	},

	categoryOptions() {
		return this.meta().categories.map(c => ({ label: c, value: c }));
	},

	// Kolom "Varian" di tabel: "3 varian · 1.2 mm, 1.5 mm"
	variantSummary(row) {
		const n = Number(row.variant_count) || 0;
		if (!n) return 'Belum ada varian';
		const active = Number(row.active_variant_count) || 0;
		const parts = [`${n} varian`];
		if (active < n) parts.push(`${n - active} INACTIVE`);
		if (row.thicknesses) parts.push(row.thicknesses);
		return parts.join(' · ');
	},

	// Kolom "Supplier" di tabel
	supplierSummary(row) {
		if (!Number(row.supplier_count)) return 'Belum ada supplier';
		const parts = [`${row.supplier_count} supplier`];
		if (row.preferred_supplier) parts.push(`utama: ${row.preferred_supplier}`);
		return parts.join(' · ');
	},

	openAdd() {
		this.form = { name: '', category: '', uom: '', price_method: 'CATALOG', status: 'ACTIVE' };
		this.busy = false;
		this.message = null;
		this.similar = [];
		this.similarFor = '';
		this.formKey = this.formKey + 1;
		showModal('mdlMaterial');
	},

	// cwMaterialForm onSearch: daftar nama mirip di pabrik user
	async searchSimilar() {
		const text = String((cwMaterialForm.model || {}).similarQuery || '').trim();
		const seq = this.similarSeq + 1;
		this.similarSeq = seq;
		if (text.length < 2) {
			this.similar = [];
			this.similarFor = text;
			return;
		}
		try {
			const rows = await q_similar.run({ kind: 'MATERIAL', text, exclude_id: '' });
			if (seq !== this.similarSeq) return;
			this.similar = rows || [];
			this.similarFor = text;
		} catch (e) {
			/* daftar mirip hanya bantuan — abaikan */
		}
	},

	async save() {
		// Baca model dulu — model di-reset saat state (Default model) berubah
		const m = cwMaterialForm.model || {};
		const data = { name: m.name, category: m.category, uom: m.uom };
		if (!data.name || !data.category || !data.uom) {
			this.message = { type: 'error', text: 'Lengkapi kategori, nama, dan Mea.' };
			return;
		}
		this.message = null;
		this.busy = true;
		let id = null;
		try {
			const rows = await a_material_add.run(data);
			id = rows && rows[0] && rows[0].id;
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlMaterial');
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };   // mis. duplikat nama + UoM
			return;
		} finally {
			this.busy = false;
		}
		closeModal('mdlMaterial');
		showAlert('Material ditambahkan. Lanjutkan dengan menambah varian.', 'success');
		if (id) {
			navigateTo('Material Detail', { id });
			return;
		}
		for (const q of [q_materials, q_material_meta]) {
			try { await q.run(); } catch (e) { /* abaikan */ }
		}
	},

	open(row) {
		navigateTo('Material Detail', { id: row.id });
	},
}
