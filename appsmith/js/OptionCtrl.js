export default {
	// R2: page Master Pilihan - pilihan dropdown model (dipakai Model List/Detail mulai R4).
	// KATEGORI, CONSTRUCTION, GENDER, UKURAN bersama semua pabrik; LAST & OUTSOLE MOLD per pabrik.
	isNew: true,
	form: { id: null, value: '', sort_order: null, status: 'ACTIVE' },
	formKey: 0,        // naik setiap modal dibuka -> cwOptionForm mengisi ulang field
	busy: false,
	message: null,     // { type, text } ditampilkan di dalam cwOptionForm
	similar: [],       // nilai mirip (fn_similar_names) untuk teks similarFor
	similarFor: '',
	similarSeq: 0,

	kindOptions: [
		{ label: 'Category', value: 'KATEGORI' },
		{ label: 'Construction', value: 'CONSTRUCTION' },
		{ label: 'Gender', value: 'GENDER' },
		{ label: 'Size', value: 'UKURAN' },
		{ label: 'Last (per factory)', value: 'LAST' },
		{ label: 'Outsole mold (per factory)', value: 'OUTSOLE_MOLD' },
	],

	statusOptions: [
		{ label: 'ACTIVE', value: 'ACTIVE' },
		{ label: 'INACTIVE', value: 'INACTIVE' },
	],

	kind() {
		return selPilihanJenis.selectedOptionValue || 'KATEGORI';
	},

	kindLabel(kind) {
		const k = kind || this.kind();
		const o = this.kindOptions.find(x => x.value === k);
		return o ? o.label.replace(' (per factory)', '') : k;
	},

	isFactoryKind(kind) {
		return ['LAST', 'OUTSOLE_MOLD'].includes(kind || this.kind());
	},

	canManage() {
		return Auth.can('manage_master');
	},

	// Pabrik user tidak ada (Brand) -> tidak bisa menambah pilihan per pabrik
	canAdd() {
		return this.canManage() && (!this.isFactoryKind() || !!(Auth.me && Auth.me.factory_id));
	},

	note() {
		return this.isFactoryKind()
			? `${this.kindLabel()} is set per factory. Each factory only sees its own.`
			: `${this.kindLabel()} is shared by all factories.`;
	},

	openForm(isNew, form) {
		this.isNew = isNew;
		this.form = form;
		this.busy = false;
		this.message = null;
		this.similar = [];
		this.similarFor = '';
		this.formKey = this.formKey + 1;
		showModal('mdlPilihan');
	},

	openAdd() {
		this.openForm(true, { id: null, kind: this.kind(), value: '', sort_order: null, status: 'ACTIVE' });
	},

	openEdit(row) {
		this.openForm(false, {
			id: row.id, kind: row.kind, value: row.value, sort_order: row.sort_order, status: row.status,
		});
	},

	formModel() {
		const kind = this.form.kind || this.kind();
		return {
			key: this.formKey,
			mode: this.isNew ? 'add' : 'edit',
			kind,
			kindLabel: this.kindLabel(kind),
			isFactoryKind: this.isFactoryKind(kind),
			factoryName: (Auth.me && Auth.me.factory_name) || '',
			form: this.form,
			statusOptions: this.statusOptions,
			similar: this.similar,
			similarFor: this.similarFor,
			busy: this.busy,
			message: this.message,
		};
	},

	// cwOptionForm onSearch: daftar nilai mirip untuk jenis ini
	async searchSimilar() {
		const text = String((cwOptionForm.model || {}).similarQuery || '').trim();
		const seq = this.similarSeq + 1;
		this.similarSeq = seq;
		if (text.length < 2) {
			this.similar = [];
			this.similarFor = text;
			return;
		}
		try {
			const rows = await q_similar.run({
				kind: 'OPTION:' + (this.form.kind || this.kind()), text, exclude_id: this.form.id || '',
			});
			if (seq !== this.similarSeq) return;
			this.similar = rows || [];
			this.similarFor = text;
		} catch (e) {
			/* daftar mirip hanya bantuan - abaikan */
		}
	},

	async save() {
		// Baca model dulu - model di-reset saat state (Default model) berubah
		const m = cwOptionForm.model || {};
		const data = {
			id: this.form.id || '',
			kind: this.form.kind || this.kind(),
			value: String(m.value || '').trim(),
			sort_order: m.sort_order === undefined || m.sort_order === null ? '' : String(m.sort_order),
			status: this.isNew ? 'ACTIVE' : m.status,
		};
		if (!data.value) {
			this.message = { type: 'error', text: 'Value is required.' };
			return;
		}
		this.message = null;
		this.busy = true;
		try {
			await a_option_save.run(data);
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlPilihan');
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };
			return;
		} finally {
			this.busy = false;
		}
		closeModal('mdlPilihan');
		showAlert(this.isNew ? `${this.kindLabel(data.kind)} added.` : `${this.kindLabel(data.kind)} saved.`, 'success');
		try { await q_options.run(); } catch (e) { /* abaikan */ }
	},
}
