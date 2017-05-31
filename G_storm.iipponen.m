function result = G_storm(a, S)

k = 0;
result = geomParametrization(S, a(k+1:k+6), S.aeInt(:,1)) +...
                geomParametrization(S, a(k+7:k+12), S.aeInt(:,2)) +...
                geomParametrization(S, a(k+13:k+18), S.aeInt(:,3)) +...
                geomParametrization(S, a(k+19:k+24), S.aeInt(:,5)) +...
                geomParametrization(S, a(k+25:k+30), S.aeInt(:,6));

end