.PHONY: all clean

all:
	ln -sfn ../xwinSDK reconstructed/xwinSDK
	ln -sfn ../d3d9x_headers reconstructed/d3d9x_headers
	$(MAKE) -C reconstructed
	cp reconstructed/UnitXP_SP3.dll UnitXP_SP3.dll

clean:
	rm -f UnitXP_SP3.dll UnitXP_SP3.lib UnitXP_SP3.exp UnitXP_SP3.pdb
	$(MAKE) -C reconstructed clean
