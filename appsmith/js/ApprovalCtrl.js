// JSObject "ApprovalCtrl" - page Persetujuan Harga (R3, ?batch=<batch id> opsional). Tampilan: Custom Widget cwPriceApproval.
// Daftar usulan harga per batch (q_price_pending); Setujui / Tolak lewat a_price_decide (izin approve_price, tanpa
// self-approval, pabrik dicek di DB). Buka material -> Material Detail tab Harga.
export default {
	// R3: page Persetujuan Harga (Manager Costing, izin approve_price). Usulan harga menunggu dari pabrik user,
	// dikelompokkan per pengajuan (batch). Keputusan per baris lewat fn_price_decide (semua atau tidak sama sekali).
	// URL ?batch=<id> (dari Beranda) -> pengajuan itu ditaruh paling atas dan disorot.
	loading: false,
	loaded: false,
	busy: false,
	message: null,     // { type, text } ditampilkan di dalam cwPriceApproval

	// Auth.pageQueries di page ini = [{ run: () => ApprovalCtrl.load() }]
	async load() {
		this.loading = true;
		try {
			await q_price_pending.run();
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return false;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };
			return false;
		} finally {
			this.loading = false;
			this.loaded = true;
		}
		return true;
	},

	// cwPriceApproval onRefresh
	reload() {
		this.message = null;
		return this.load();
	},

	// q_price_pending (urut created_at) -> [{ batch_id, material_id, material_name, uom, proposed_by, proposed_at, items }]
	batches() {
		const map = {};
		const list = [];
		(q_price_pending.data || []).forEach(r => {
			let b = map[r.batch_id];
			if (!b) {
				b = {
					batch_id: r.batch_id, material_id: r.material_id, material_name: r.material_name, uom: r.uom,
					proposed_by: r.created_by, proposed_at: r.created_at, items: [],
				};
				map[r.batch_id] = b;
				list.push(b);
			}
			b.items.push({
				id: r.id, code: r.code, color: r.color, thickness_label: r.thickness_label, supplier_name: r.supplier_name,
				price: r.price, currency: r.currency, valid_from: r.valid_from, reference: r.reference,
				cur_price: r.cur_price, cur_currency: r.cur_currency, cur_valid_from: r.cur_valid_from, problem: r.problem,
			});
		});
		return list;
	},

	// Default model cwPriceApproval: {{ApprovalCtrl.model()}}
	model() {
		return {
			loaded: this.loaded,
			loading: this.loading,
			busy: this.busy,
			message: this.message,
			focusBatch: appsmith.URL.queryParams.batch || '',
			batches: this.batches(),
		};
	},

	// cwPriceApproval onDecide - baca aksi dari model widget dulu (model di-reset saat state berubah)
	async decide() {
		const a = (cwPriceApproval.model || {}).action || {};
		const ids = Array.isArray(a.ids) ? a.ids : [];
		if (!ids.length || (a.decision !== 'APPROVE' && a.decision !== 'REJECT')) return;
		this.busy = true;
		this.message = null;
		try {
			await a_price_decide.run({ ids: JSON.stringify(ids), decision: a.decision, reason: a.reason || '' });
			const n = Number(((a_price_decide.data || [])[0] || {}).n) || ids.length;
			this.message = {
				type: 'success',
				text: a.decision === 'APPROVE' ? `${n} price(s) approved. The old price ends on the new price start date.`
					: `${n} price(s) rejected.`,
			};
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };
		} finally {
			this.busy = false;
		}
		await this.load();
	},

	// cwPriceApproval onOpenMaterial
	openMaterial() {
		const id = (cwPriceApproval.model || {}).material_id;
		if (id) navigateTo('Material Detail', { id });
	},
}
