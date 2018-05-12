#ifndef SEQ_EXPRSTAGE_H
#define SEQ_EXPRSTAGE_H

#include "expr.h"
#include "cell.h"
#include "stage.h"

namespace seq {

	class ExprStage : public Stage {
	private:
		Expr *expr;
	public:
		explicit ExprStage(Expr *expr);
		void validate() override;
		void codegen(llvm::Module *module) override;
		static ExprStage& make(Expr *expr);
	};

	class CellStage : public Stage {
	private:
		Cell *cell;
	public:
		explicit CellStage(Cell *cell);
		void codegen(llvm::Module *module) override;
		static CellStage& make(Cell *cell);
	};

	class AssignStage : public Stage {
	private:
		Cell *cell;
		Expr *value;
	public:
		explicit AssignStage(Cell *cell, Expr *value);
		void codegen(llvm::Module *module) override;
		static AssignStage& make(Cell *cell, Expr *value);
	};

}

#endif /* SEQ_EXPRSTAGE_H */
